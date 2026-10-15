# Mainline Linux on Xiaomi Poco F3 (alioth)

This repository maintains mainline Linux (kernel 6.x/7.x) porting packages, postmarketOS packages, and Fedora ARM64 (KDE Plasma Mobile) integration for the **Xiaomi Poco F3** (codename: `alioth`).

---

## 1. Hardware Specifications

| Component | Specification |
| :--- | :--- |
| **SoC** | Qualcomm Snapdragon 870 (SM8250-AC / Kona) |
| **CPU** | 1x Cortex-A77 (Prime @ 3.2GHz) + 3x Cortex-A77 (Gold @ 2.42GHz) + 4x Cortex-A55 (Silver @ 1.8GHz) |
| **GPU** | Adreno 650 (Open-source Freedreno / Turnip Vulkan) |
| **Display** | 6.67" AMOLED Samsung AMS667XX01 (1080x2400 @ 120Hz) |
| **Touchscreen** | FocalTech FT8756 |
| **Modem** | Qualcomm Snapdragon X55 (SDX55 flashless via PCIe MHI) |
| **WLAN & BT** | Qualcomm Atheros QCA6390 (Wi-Fi 6 via PCIe ath11k + Bluetooth via UART) |
| **Audio** | Dual Cirrus Logic CS35L41 Hardware Smart Amplifiers |
| **Storage** | 128 GB / 256 GB UFS 3.1 |

---

## 2. Hardware Support Status

| Feature | Status | Notes |
| :--- | :--- | :--- |
| **Display & Backlight** | ✅ Working | Built-in driver `panel-samsung-ams667xx01` |
| **Touchscreen** | ✅ Working | Built-in driver `touchscreen-ft8756` |
| **GPU Acceleration (3D)** | ✅ Working | Mesa Freedreno & Turnip Vulkan |
| **Wi-Fi 6 (802.11ax)** | ✅ Working | ath11k PCI, powersave disabled for stability |
| **Bluetooth 5.1** | ✅ Working | hci_qca via `alioth-bluetooth.service` |
| **Audio (Speaker & Earpiece)** | ✅ Working | Calibrated UCM2 profile & ALSA volume boost |
| **Cellular 5G / 4G Data** | ✅ Working | SDX55 via MHI/RmNet, QRTR, and tqftpserv |
| **Dual SIM Switching** | ✅ Working | Plasma Mobile GUI shortcuts & `alioth-switch-sim` CLI |
| **Battery & Charging** | ✅ Working | Accurate battery and charging state reporting |
| **Sensors** | ✅ Working | Sensor udev rules via `libssc` |
| **Camera** | 🟡 In Progress | Initial patches available; ISP/CamX integration ongoing |

---

## 3. Documentation

Documentation is organized into dedicated user and developer guides:

### 📖 User Guides
* **[Installation Guide](docs/user/installation.md)**: Step-by-step instructions for flashing postmarketOS and standalone Fedora ARM64.
* **[Dual Boot Guide (AOSP + Fedora)](docs/user/dualboot.md)**: 50/50 UFS partitioning and running Android alongside Fedora Linux.
* **[Daily Configuration & Usage](docs/user/configuration.md)**: Audio volume boost, SIM slot switching, SSH remote access, and DNF update safety.

### 🛠️ Developer Guides
* **[Kernel Architecture & defconfig](docs/dev/kernel.md)**: 48-bit virtual addressing, the `CONFIG_EFI_ZBOOT` issue, built-in drivers, and out-of-tree module compilation.
* **[Hardware UART Debugging](docs/dev/uart-debugging.md)**: PCB test points, 1.8V transistor level shifter, Arduino bridge code, and reading ABL logs.
* **[SDX55 5G Modem Bring-Up](docs/dev/modem-bringup.md)**: Flashless PCIe MHI architecture, QRTR, Sahara/EFS daemons, and ModemManager integration.
* **[Wi-Fi & Bluetooth Bring-Up](docs/dev/wifi-bluetooth.md)**: QCA6390 MHI power state transitions and Bluetooth UART initialization.
* **[Device Tree & Audio](docs/dev/dts-and-audio.md)**: DTS extraction from Android vendor boot, audio buzz debugging, and UCM2 profiles.
* **[Fedora Rootfs Provisioning Automation](docs/dev/fedora-rootfs.md)**: Architecture of `prepare-fedora-rootfs.sh` and automated sparse image creation.

---

## 4. Prebuilt Tools Included

- **`tools/parted/`**: Self-contained ARM64 GNU Parted bundle (includes musl dynamic loader and required shared libraries). Ready to push to `/tmp` in custom recovery (`OrangeFox`/`TWRP`) to partition UFS storage without requiring a build environment.
- **`tools/qbootctl` / `device-xiaomi-alioth/qbootctl`**: Statically linked ARM64 `qbootctl` binary (compiled from [linux-msm/qbootctl](https://github.com/linux-msm/qbootctl)) to switch active A/B slots from within Linux. Injected into `/usr/local/bin/qbootctl` automatically on Fedora rootfs images.

---

## 5. Quick Flash Summary (TL;DR)

### Standalone Fedora on `userdata`
```sh
# 1. Build prepared rootfs sparse image
sudo ./build-fedora-rootfs.sh /path/to/Fedora-Disk.raw fedora-rootfs.simg

# 2. Flash via Fastboot
fastboot erase dtbo_b
fastboot flash boot_b ~/boot_fedora.img
fastboot flash userdata ~/fedora-rootfs.simg
fastboot set_active b
fastboot reboot
```

### Dual Boot (Switching OS via Fastboot)
```sh
fastboot set_active a && fastboot reboot   # Boot Android
fastboot set_active b && fastboot reboot   # Boot Fedora
```

---

## 6. Repository Layout

```
pmaports-alioth/
├── docs/                             # Structured documentation
│   ├── user/                         # End-user guides (installation, dual boot, config)
│   └── dev/                          # Developer technical docs (kernel, modem, uart, dts)
├── tools/                            # Prebuilt binaries
│   ├── parted/                       # ARM64 parted bundle for recovery
│   └── qbootctl                      # Static A/B slot switching binary
├── device-xiaomi-alioth/              # postmarketOS device package
│   ├── alsa-ucm-conf/                # ALSA UCM2 audio profiles (alioth.conf, HiFi.conf)
│   ├── modem-services/               # SDX55 modem daemons & bring-up scripts
│   ├── alioth-bluetooth*             # Bluetooth init script and systemd unit
│   └── qbootctl                      # Static qbootctl binary for Fedora / pmOS
├── linux-postmarketos-qcom-sm8250-alioth/ # Mainline kernel package
├── firmware-xiaomi-alioth/            # Non-free firmware package
├── Notes/                            # Raw logs (dmesgs, dts, uart_logs, fastboot dump)
├── prepare-fedora-rootfs.sh          # Fedora rootfs hardware provisioner
├── build-fedora-rootfs.sh            # Automated Fedora sparse image builder
├── update_folder.sh                  # Sync repo packages -> pmbootstrap cache
└── store_folder_in_repo.sh           # Sync pmbootstrap cache -> repo
```
