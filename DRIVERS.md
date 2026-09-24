# Драйверы для сборки

MSI MPG Z490 GAMING PLUS (MS-7C75) · Intel Core i5-10600KF · GeForce RTX 3060 Ti GDDR6X · 2× MSI M390 NVMe

Версии проверены 25.09.2026. Если на сайте производителя есть версия новее, бери её.

## Порядок установки

| # | Что | Версия | Дата | Где скачать |
|---|---|---|---|---|
| 0 | **BIOS** (ставить до Windows) | **7C75vAF1** | 16.04.2026 | [MSI → Support → BIOS](https://www.msi.com/Motherboard/MPG-Z490-GAMING-PLUS/support) |
| 1 | Intel Chipset Device Software | **10.1.20658.8883** | 08.01.2026 | [intel.com](https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html) |
| 2 | Intel Management Engine (CSME) | **2618.9.30.0** | 17.06.2026 | [intel.com](https://www.intel.com/content/www/us/en/download/682431/intel-management-engine-drivers-for-windows-10-and-windows-11.html) |
| 3 | Realtek RTL8125 2.5GbE (LAN) | **11.031.50** (Win11, NetAdapterCx) | 28.08.2026 | [realtek.com](https://www.realtek.com/Download/List?cate_id=584) |
| 4 | Realtek HD Audio | последняя с сайта MSI | — | [MSI → Support → Drivers → On-Board Audio](https://www.msi.com/Motherboard/MPG-Z490-GAMING-PLUS/support) |
| 5 | NVIDIA GeForce Game Ready | **617.14 WHQL** | 22.09.2026 | [nvidia.com/drivers](https://www.nvidia.com/en-us/drivers/) или NVIDIA App |
| — | Wi-Fi Realtek RTL8192EE | из Windows Update | — | ставится сам |
| — | NVMe MSI M390, гарнитура C-Media, мышь, клавиатура | встроенные в Windows | — | ничего не ставить |

После пункта 5 — перезагрузка, затем `run.bat` → пункт **8 (Отчёт)**: он покажет устройства без драйверов.

## Пояснения

**BIOS 7C75vAF1.** Сейчас стоит A80 (2021). В AF1 обновлены ключи Secure Boot: старые сертификаты Microsoft 2011 года истекают в 2026-м, и без новых ключей плата не сможет получать обновления защиты загрузки Windows. Ещё в AE закрыты уязвимости LogoFAIL и CVE-2024-36877, в AD обновлён микрокод процессора. Прошивать через **M-FLASH** с флешки FAT32, не выключать ПК во время прошивки. После прошивки настройки BIOS сбрасываются — выставь заново пункты ниже.

**Настройки BIOS после прошивки** (F7 — расширенный режим; если пункт не находится, в BIOS есть поиск — значок лупы вверху):
- **XMP** — кнопка **XMP Profile** на главном экране (слева вверху) → Profile 1. Иначе память работает на 2133/2666 МГц.
- **Загрузка только UEFI (CSM выкл.)** — `SETTINGS → Advanced → Windows OS Configuration` → «BIOS UEFI/CSM Mode» = **UEFI** (в старых прошивках пункт называется «Windows 10 WHQL Support» = Enabled). Ставить до установки Windows.
- **Resizable BAR** — `SETTINGS → Advanced → PCIe/PCI Sub-system Settings` → «Above 4G memory/Crypto Currency mining» = **Enabled**, «Re-Size BAR Support» = **Enabled**. Появляется только в BIOS A6 и новее и только при загрузке в режиме UEFI. RTX 3060 Ti поддерживает, +несколько % FPS в части игр.
- **TPM 2.0** — `SETTINGS → Security → Trusted Computing` → «Security Device Support» = **Enable**, «TPM Device Selection» = **PTT**.
- **Secure Boot** — `SETTINGS → Security → Secure Boot` → **Enabled**.

Разделы `SETTINGS → Advanced`, `Security`, `PCIe/PCI Sub-system Settings`, кнопки XMP Profile и M-FLASH описаны в руководстве к плате (E7C75 v1.1, 2023). Пункты Re-Size BAR и названия внутри подменю в руководстве не описаны — они приведены по типовому MSI Click BIOS 5 для плат 400/500-серии, на экране могут немного отличаться.

**Intel ME.** Для 400-серии достаточно пакета «Consumer» из архива: `ME_SW_DCH` → `SetupME.exe`. Корпоративные компоненты (AMT) на этой плате не нужны.

**Realtek LAN.** Драйвер с realtek.com новее, чем на сайте MSI. Бери вариант **Win11 Auto Installation Program (NetAdapterCx)**.

**Realtek Audio.** Бери именно с сайта MSI: в пакете производителя правильная раскладка разъёмов под эту плату. Универсальные сборки Realtek UAD могут путать передние и задние разъёмы.

**NVIDIA.** Game Ready — для игр. Если важнее стабильность в Blender, DaVinci, OBS и т. п. — ветка **Studio** на той же странице. При смене драйвера с глючного можно начисто удалить старый через [DDU](https://www.wagnardsoft.com/display-driver-uninstaller-DDU-) в безопасном режиме. В NVIDIA App при установке можно снять лишние компоненты.

## Не ставить

- Драйвер-паки (DriverPack, Driver Booster, Snappy и т. п.).
- Intel Graphics — у i5-10600KF нет встроенной графики.
- MSI Center целиком — если нужна только подсветка, ставь из него один модуль Mystic Light.
