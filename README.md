# Mainline Linux on Xiaomi Poco F3 (alioth)

Repository ini memelihara porting mainline Linux (kernel 6.x/7.x), package postmarketOS, dan integrasi Fedora ARM64 (KDE Plasma Mobile) untuk **Xiaomi Poco F3** (codename: `alioth`).

---

## 1. Spesifikasi Hardware

| Komponen | Spesifikasi |
| :--- | :--- |
| **SoC** | Qualcomm Snapdragon 870 (SM8250-AC / Kona) |
| **CPU** | 1x Cortex-A77 (Prime @ 3.2GHz) + 3x Cortex-A77 (Gold @ 2.42GHz) + 4x Cortex-A55 (Silver @ 1.8GHz) |
| **GPU** | Adreno 650 (Open source Freedreno / Turnip Vulkan) |
| **Layar** | 6.67" AMOLED Samsung AMS667XX01 (1080x2400 @ 120Hz) |
| **Touchscreen** | FocalTech FT8756 |
| **Modem** | Qualcomm Snapdragon X55 (SDX55 flashless via PCIe MHI) |
| **WLAN & BT** | Qualcomm Atheros QCA6390 (Wi-Fi 6 via PCIe ath11k + Bluetooth via UART) |
| **Audio** | Dual Cirrus Logic CS35L41 Hardware Smart Amplifier |
| **Penyimpanan** | 128 GB / 256 GB UFS 3.1 |

---

## 2. Status Dukungan Hardware

| Fitur | Status | Catatan |
| :--- | :--- | :--- |
| **Layar & Backlight** | ✅ Berfungsi | Driver built-in `panel-samsung-ams667xx01` |
| **Touchscreen** | ✅ Berfungsi | Driver built-in `touchscreen-ft8756` |
| **Akselerasi GPU (3D)** | ✅ Berfungsi | Mesa Freedreno & Turnip Vulkan |
| **Wi-Fi 6 (802.11ax)** | ✅ Berfungsi | ath11k PCI, powersave dinonaktifkan untuk stabilitas |
| **Bluetooth 5.1** | ✅ Berfungsi | hci_qca via `alioth-bluetooth.service` |
| **Audio (Speaker & RCV)** | ✅ Berfungsi | UCM2 profile & ALSA volume boost terkalibrasi |
| **Koneksi Data 5G / 4G** | ✅ Berfungsi | SDX55 via MHI/RmNet, QRTR, dan tqftpserv |
| **Dual SIM Switching** | ✅ Berfungsi | GUI shortcut Plasma Mobile & CLI `alioth-switch-sim` |
| **Baterai & Pengisian Daya**| ✅ Berfungsi | Status baterai terbaca akurat |
| **Sensors** | ✅ Berfungsi | Udev rules `libssc` |
| **Kamera** | 🟡 Dalam Pengembangan| Patch awal tersedia, integrasi ISP/CamX sedang dikerjakan |

---

## 3. Dokumentasi

Dokumentasi telah dipisahkan secara terstruktur untuk pengguna dan pengembang:

### 📖 Dokumentasi Pengguna (User Guides)
* **[Panduan Instalasi Lengkap](docs/user/installation.md)**: Panduan langkah demi langkah flashing postmarketOS dan Fedora ARM64 standalone.
* **[Panduan Dual Boot (AOSP + Fedora)](docs/user/dualboot.md)**: Panduan membagi storage UFS 50/50 dan menjalankan Android & Linux berdampingan.
* **[Konfigurasi Harian & Tips](docs/user/configuration.md)**: Pengaturan volume audio, switching SIM card, akses SSH, dan keamanan update DNF.

### 🛠️ Dokumentasi Pengembang (Developer Guides)
* **[Arsitektur Kernel & defconfig](docs/dev/kernel.md)**: Virtual address 48-bit, masalah `CONFIG_EFI_ZBOOT`, driver built-in, dan out-of-tree modules.
* **[Hardware UART Debugging](docs/dev/uart-debugging.md)**: Pinout UART PCB, rangkaian level shifter 1.8V, bridge Arduino, dan pembacaan log ABL.
* **[Bring-Up Modem SDX55](docs/dev/modem-bringup.md)**: Arsitektur flashless PCIe MHI, QRTR, Sahara/EFS helper, dan integrasi ModemManager.
* **[Bring-Up Wi-Fi & Bluetooth](docs/dev/wifi-bluetooth.md)**: Solusi transisi MHI QCA6390 dan inisialisasi UART Bluetooth.
* **[Device Tree & Audio](docs/dev/dts-and-audio.md)**: Ekstraksi DTS dari vendor boot Android, debugging buzz audio, dan UCM2.
* **[Otomatisasi Rootfs Fedora](docs/dev/fedora-rootfs.md)**: Arsitektur `prepare-fedora-rootfs.sh` dan pembuatan sparse image Fedora.

---

## 4. Prebuilt Tools dalam Repository

- **`tools/parted/`**: Bundle GNU Parted ARM64 mandiri (disertai musl dynamic linker dan pustaka pendukung). Siap dipush ke `/tmp` recovery Android (`OrangeFox`/`TWRP`) untuk mempartisi UFS tanpa perlu build environment.
- **`tools/qbootctl` / `device-xiaomi-alioth/qbootctl`**: Biner statis ARM64 `qbootctl` (dikompilasi dari [linux-msm/qbootctl](https://github.com/linux-msm/qbootctl)) untuk mengganti active A/B slot langsung dari dalam Linux. Otomatis disuntikkan ke `/usr/local/bin/qbootctl` pada image Fedora.

---

## 5. Ringkasan Quick Flash (TL;DR)

### Single Boot Fedora pada `userdata`
```sh
# 1. Siapkan rootfs
sudo ./build-fedora-rootfs.sh /path/to/Fedora-Disk.raw fedora-rootfs.simg

# 2. Flash via Fastboot
fastboot erase dtbo_b
fastboot flash boot_b ~/boot_fedora.img
fastboot flash userdata ~/fedora-rootfs.simg
fastboot set_active b
fastboot reboot
```

### Dual Boot (Pindah OS via Fastboot)
```sh
fastboot set_active a && fastboot reboot   # Boot ke Android
fastboot set_active b && fastboot reboot   # Boot ke Fedora
```

---

## 6. Struktur Direktori Repository

```
pmaports-alioth/
├── docs/                             # Dokumentasi terstruktur
│   ├── user/                         # Panduan pengguna (instalasi, dualboot, config)
│   └── dev/                          # Dokumentasi pengembang (kernel, modem, uart, dts)
├── tools/                            # Utilitas prebuilt
│   ├── parted/                       # ARM64 parted bundle untuk recovery
│   └── qbootctl                      # Biner statis switching A/B slot
├── device-xiaomi-alioth/              # Package postmarketOS device
│   ├── alsa-ucm-conf/                # Profil audio UCM2 (alioth.conf, HiFi.conf)
│   ├── modem-services/               # Daemon & script bring-up modem SDX55
│   ├── alioth-bluetooth*             # Service & script inisialisasi Bluetooth
│   └── qbootctl                      # Biner statis qbootctl untuk Fedora / pmOS
├── linux-postmarketos-qcom-sm8250-alioth/ # Package kernel mainline
├── firmware-xiaomi-alioth/            # Package firmware non-free
├── Notes/                            # Log mentah (dmesgs, dts, uart_logs, fastboot dump)
├── prepare-fedora-rootfs.sh          # Script provisioning Fedora rootfs
├── build-fedora-rootfs.sh            # Builder otomatis sparse image Fedora
├── update_folder.sh                  # Push perubahan repo -> cache pmbootstrap
└── store_folder_in_repo.sh           # Pull perubahan cache pmbootstrap -> repo
```
