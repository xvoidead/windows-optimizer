# Оптимизатор Windows 11 под MSI Z490 / i5-10600KF / RTX 3060 Ti / NVMe.
# Все изменения реестра, служб и схемы питания сохраняются в backup.json
# рядом со скриптом и откатываются пунктом меню «Откатить все изменения».

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- Запуск от имени администратора ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$BackupFile = Join-Path $PSScriptRoot 'backup.json'

# --- Резервная копия ---
function Load-Backup {
    if (Test-Path $BackupFile) {
        $b = Get-Content $BackupFile -Raw -Encoding UTF8 | ConvertFrom-Json
        return @{
            Registry    = @($b.Registry | Where-Object { $_ })
            Services    = @($b.Services | Where-Object { $_ })
            PowerScheme = $b.PowerScheme
        }
    }
    return @{ Registry = @(); Services = @(); PowerScheme = $null }
}

function Save-Backup {
    $script:Backup | ConvertTo-Json -Depth 5 | Set-Content $BackupFile -Encoding UTF8
}

$script:Backup = Load-Backup

function Set-Tweak {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    $id = "$Path\$Name"
    # Исходное значение запоминаем только при первом изменении
    if (-not ($script:Backup.Registry | Where-Object { $_.Id -eq $id })) {
        $existed = $false; $old = $null; $oldType = $null
        if (Test-Path $Path) {
            $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $item) {
                $existed = $true
                $old = $item.$Name
                $oldType = (Get-Item $Path).GetValueKind($Name).ToString()
            }
        }
        $script:Backup.Registry += [pscustomobject]@{
            Id = $id; Path = $Path; Name = $Name; Existed = $existed; Value = $old; Type = $oldType
        }
    }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Set-ServiceStart {
    param([string]$Name, [string]$Mode)  # auto | demand | disabled
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    if (-not ($script:Backup.Services | Where-Object { $_.Name -eq $Name })) {
        $script:Backup.Services += [pscustomobject]@{ Name = $Name; StartType = $svc.StartType.ToString() }
    }
    if ($Mode -eq 'disabled') { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
    sc.exe config $Name start= $Mode | Out-Null
}

function Write-Step([string]$Text) { Write-Host "  -> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "  [!] $Text" -ForegroundColor Yellow }

# --- Точка восстановления ---
function New-RestorePoint {
    Write-Step 'Создаю точку восстановления системы...'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'Перед оптимизатором' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Ok 'Точка восстановления создана'
    } catch {
        Write-Warn "Не удалось создать точку восстановления: $($_.Exception.Message)"
        Write-Warn 'Windows разрешает не больше одной точки в сутки, это нормально, если сегодня она уже была.'
    }
}

# --- 1. Питание ---
function Optimize-Power {
    Write-Step 'Включаю схему питания «Максимальная производительность»...'
    if (-not $script:Backup.PowerScheme) {
        $current = (powercfg /getactivescheme) -replace '.*:\s*([0-9a-fA-F-]{36}).*', '$1'
        $script:Backup.PowerScheme = $current.Trim()
    }
    $ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    $existing = powercfg /list | Select-String -Pattern '([0-9a-fA-F-]{36}).*(Ultimate|Максимальная)'
    if ($existing) {
        $guid = $existing.Matches[0].Groups[1].Value
    } else {
        $out = powercfg -duplicatescheme $ultimate
        $guid = ([regex]::Match($out, '[0-9a-fA-F-]{36}')).Value
    }
    if ($guid) {
        powercfg /setactive $guid
        Write-Ok "Активна схема $guid"
    } else {
        powercfg /setactive SCHEME_MIN
        Write-Warn 'Максимальная производительность недоступна, включена «Высокая производительность»'
    }
    # Без гибернации: освобождает место (hiberfil.sys = ~40% ОЗУ) и отключает «быстрый запуск»,
    # который часто мешает двойной загрузке с Linux и повреждает общий NTFS-раздел.
    powercfg /hibernate off
    Write-Ok 'Гибернация и быстрый запуск выключены'
    Save-Backup
}

# --- 2. Игры и видеокарта ---
function Optimize-Gaming {
    Write-Step 'Настраиваю игровой режим и видеокарту...'
    Set-Tweak 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
    Set-Tweak 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
    # Аппаратное планирование GPU: RTX 3060 Ti поддерживает, нужна перезагрузка
    Set-Tweak 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
    # Фоновая запись Xbox Game Bar отнимает ресурсы
    Set-Tweak 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    Set-Tweak 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    # Отключение «повышенной точности указателя» (ускорения мыши)
    Set-Tweak 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
    Set-Tweak 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
    Set-Tweak 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
    Save-Backup
    Write-Ok 'Игровой режим включён, фоновая запись и ускорение мыши выключены, HAGS включён (после перезагрузки)'
}

# --- 3. Приватность и реклама ---
function Optimize-Privacy {
    Write-Step 'Отключаю телеметрию, рекламу и подсказки...'
    Set-ServiceStart 'DiagTrack' 'disabled'
    Set-ServiceStart 'dmwappushservice' 'disabled'
    Set-Tweak 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
                   'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
                   'SystemPaneSuggestionsEnabled', 'SilentInstalledAppsEnabled',
                   'SoftLandingEnabled') {
        Set-Tweak $cdm $n 0
    }
    # Поиск Bing в меню «Пуск»
    Set-Tweak 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-Tweak 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
    Save-Backup
    Write-Ok 'Телеметрия, рекламный ID, рекомендации и веб-поиск в «Пуске» выключены'
}

# --- 4. Очистка ---
function Get-FreeGB { [math]::Round((Get-PSDrive ($env:SystemDrive.TrimEnd(':'))).Free / 1GB, 2) }

function Clear-System {
    $before = Get-FreeGB
    Write-Step 'Удаляю временные файлы...'
    foreach ($dir in "$env:TEMP", "$env:SystemRoot\Temp") {
        Get-ChildItem $dir -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Step 'Очищаю кэш Windows Update...'
    Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
    Get-ChildItem "$env:SystemRoot\SoftwareDistribution\Download" -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv, bits -ErrorAction SilentlyContinue
    Write-Step 'Очищаю корзину...'
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Step 'Удаляю старые версии компонентов Windows (DISM, может занять несколько минут)...'
    Dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet /NoRestart | Out-Null
    $after = Get-FreeGB
    Write-Ok "Освобождено: $([math]::Round($after - $before, 2)) ГБ (свободно $after ГБ)"
}

# --- 5. SSD ---
function Optimize-SSD {
    Write-Step 'Проверяю TRIM...'
    $trim = fsutil behavior query DisableDeleteNotify
    if ($trim -match 'NTFS DisableDeleteNotify = 1') {
        fsutil behavior set DisableDeleteNotify 0 | Out-Null
        Write-Ok 'TRIM был выключен, включил'
    } else {
        Write-Ok 'TRIM включён'
    }
    Write-Step 'Запускаю ReTrim на всех SSD...'
    Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -eq 'NTFS' } | ForEach-Object {
        try {
            Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -ErrorAction Stop
            Write-Ok "Диск $($_.DriveLetter): готово"
        } catch {
            Write-Warn "Диск $($_.DriveLetter): $($_.Exception.Message)"
        }
    }
}

# --- 6. Проверка системных файлов ---
function Repair-System {
    Write-Step 'DISM: проверяю и восстанавливаю образ Windows (10–20 минут)...'
    Dism.exe /Online /Cleanup-Image /RestoreHealth
    Write-Step 'SFC: проверяю системные файлы...'
    sfc.exe /scannow
    Write-Ok 'Проверка завершена'
}

# --- 7. Отчёт о системе ---
function Show-Report {
    Write-Host ''
    Write-Host '=== Драйверы ===' -ForegroundColor Magenta
    Get-CimInstance Win32_VideoController | ForEach-Object {
        Write-Host ("  Видеокарта: {0}, драйвер {1} от {2:dd.MM.yyyy}" -f $_.Name, $_.DriverVersion, $_.DriverDate)
    }
    $broken = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'OK' -and $_.Class }
    if ($broken) {
        Write-Warn 'Устройства с проблемами (нужен драйвер):'
        $broken | ForEach-Object { Write-Host "     $($_.FriendlyName) [$($_.Class)] — $($_.Status)" }
    } else {
        Write-Ok 'Все устройства работают'
    }
    $mei = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Management Engine' }
    if (-not $mei) { Write-Warn 'Intel Management Engine не установлен (скачай с сайта MSI)' }

    Write-Host ''
    Write-Host '=== Автозагрузка ===' -ForegroundColor Magenta
    Get-CimInstance Win32_StartupCommand | ForEach-Object { Write-Host "  $($_.Name)  ($($_.Location))" }
    Write-Host '  Лишнее отключай в Диспетчере задач -> «Автозагрузка приложений».' -ForegroundColor DarkGray

    Write-Host ''
    Write-Host '=== Диски ===' -ForegroundColor Magenta
    Get-PhysicalDisk | ForEach-Object {
        Write-Host ("  {0}: {1}, здоровье {2}" -f $_.FriendlyName, $_.MediaType, $_.HealthStatus)
    }
    Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
        $pct = if ($_.Size) { [math]::Round(100 * $_.SizeRemaining / $_.Size) } else { 0 }
        $color = if ($pct -lt 15) { 'Yellow' } else { 'Gray' }
        Write-Host ("  {0}: свободно {1:N1} из {2:N1} ГБ ({3}%)" -f $_.DriveLetter, ($_.SizeRemaining / 1GB), ($_.Size / 1GB), $pct) -ForegroundColor $color
    }

    Write-Host ''
    Write-Host '=== Память ===' -ForegroundColor Magenta
    Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        Write-Host ("  {0} ГБ, {1} МГц (настроено {2} МГц)" -f ($_.Capacity / 1GB), $_.Speed, $_.ConfiguredClockSpeed)
    }
    $mem = Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1
    if ($mem -and $mem.ConfiguredClockSpeed -lt $mem.Speed) {
        Write-Warn 'Память работает ниже номинала: включи XMP в BIOS (Extreme Memory Profile).'
    } elseif ($mem -and $mem.ConfiguredClockSpeed -le 2666) {
        Write-Warn 'Частота памяти 2666 МГц или ниже: проверь, включён ли XMP в BIOS.'
    }
}

# --- Откат ---
function Undo-All {
    if (-not (Test-Path $BackupFile)) { Write-Warn 'Резервной копии нет, откатывать нечего'; return }
    Write-Step 'Возвращаю реестр...'
    foreach ($r in $script:Backup.Registry) {
        if ($r.Existed) {
            if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
            New-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Value -PropertyType $r.Type -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $r.Path -Name $r.Name -ErrorAction SilentlyContinue
        }
    }
    Write-Step 'Возвращаю службы...'
    $map = @{ Automatic = 'auto'; Manual = 'demand'; Disabled = 'disabled' }
    foreach ($s in $script:Backup.Services) {
        $mode = $map[$s.StartType]
        if ($mode) {
            sc.exe config $s.Name start= $mode | Out-Null
            if ($mode -eq 'auto') { Start-Service $s.Name -ErrorAction SilentlyContinue }
        }
    }
    if ($script:Backup.PowerScheme) {
        Write-Step 'Возвращаю схему питания...'
        powercfg /setactive $script:Backup.PowerScheme
    }
    Remove-Item $BackupFile -Force
    $script:Backup = @{ Registry = @(); Services = @(); PowerScheme = $null }
    Write-Ok 'Всё возвращено. Гибернацию, если нужна, включи командой: powercfg /hibernate on'
    Write-Ok 'Перезагрузи компьютер.'
}

# --- Меню ---
function Show-Menu {
    Clear-Host
    Write-Host '==============================================' -ForegroundColor DarkCyan
    Write-Host '   Оптимизатор Windows 11' -ForegroundColor White
    Write-Host '   MSI Z490 / i5-10600KF / RTX 3060 Ti' -ForegroundColor DarkGray
    Write-Host '==============================================' -ForegroundColor DarkCyan
    Write-Host '  1. Всё сразу (пункты 2–6, рекомендуется)'
    Write-Host '  2. Питание: максимальная производительность'
    Write-Host '  3. Игры: Game Mode, HAGS, без записи и ускорения мыши'
    Write-Host '  4. Приватность: телеметрия, реклама, Bing в «Пуске»'
    Write-Host '  5. Очистка временных файлов и кэша обновлений'
    Write-Host '  6. SSD: TRIM и ReTrim'
    Write-Host '  7. Проверка и починка системных файлов (DISM + SFC)'
    Write-Host '  8. Отчёт: драйверы, автозагрузка, диски, память'
    Write-Host '  9. Откатить все изменения' -ForegroundColor Yellow
    Write-Host '  0. Выход'
    Write-Host ''
}

while ($true) {
    Show-Menu
    $choice = Read-Host 'Выбери пункт'
    Write-Host ''
    switch ($choice) {
        '1' { New-RestorePoint; Optimize-Power; Optimize-Gaming; Optimize-Privacy; Clear-System; Optimize-SSD
              Write-Host ''; Write-Ok 'Готово. Перезагрузи компьютер, чтобы всё применилось.' }
        '2' { New-RestorePoint; Optimize-Power }
        '3' { New-RestorePoint; Optimize-Gaming }
        '4' { New-RestorePoint; Optimize-Privacy }
        '5' { Clear-System }
        '6' { Optimize-SSD }
        '7' { Repair-System }
        '8' { Show-Report }
        '9' { Undo-All }
        '0' { exit }
        default { Write-Warn 'Нет такого пункта' }
    }
    Write-Host ''
    Read-Host 'Нажми Enter, чтобы вернуться в меню' | Out-Null
}
