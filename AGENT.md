# AGENT.md - Repository Guide for Xiaomi Poco F3 (alioth)

## 1. Project Overview

This repository maintains mainline Linux / postmarketOS porting and Fedora ARM64 integration packages for the **Xiaomi Poco F3** (codename: `alioth`).

- **SoC**: Qualcomm Snapdragon 865/870 (SM8250 / Kona)
- **CPU**: 1x Cortex-A77 (Prime) + 3x Cortex-A77 (Gold) + 4x Cortex-A55 (Silver)
- **GPU**: Adreno 650
- **Modem**: Qualcomm Snapdragon X55 (SDX55 via MHI/PCIe)
- **Target OS**: postmarketOS (edge / alpine-based) and Fedora ARM64 (KDE Mobile)

---

## 2. Repository Layout

```
pmaports-alioth/
├── device-xiaomi-alioth/              # postmarketOS device package
│   ├── APKBUILD                      # Device package definition & dependencies
│   ├── deviceinfo                    # PMOS hardware flags & partition table specs
│   ├── alsa-ucm-conf/                # ALSA Use Case Manager profiles (alioth.conf, HiFi.conf)
│   ├── modem-services/               # Systemd services & scripts for SDX55 modem bring-up
│   ├── alioth-bluetooth*             # Bluetooth init script and systemd unit
│   └── 81-libssc-xiaomi-alioth.rules # Sensor udev configuration
├── linux-postmarketos-qcom-sm8250-alioth/ # Mainline kernel package
│   ├── APKBUILD                      # Kernel build script (SM8250 mainline fork)
│   ├── config-*                      # Kernel defconfig (aarch64)
│   └── *.patch                       # DTS, panel, touchscreen, and modem patches
├── firmware-xiaomi-alioth/            # Non-free firmware package
│   ├── APKBUILD                      # Firmware extraction & packaging
│   └── *.files                       # Lists of firmware files for initramfs & sensors
├── docs/                             # Structured documentation
│   ├── user/                         # End-user guides (installation, dualboot, config)
│   └── dev/                          # Developer technical docs (kernel, modem, uart, dts)
├── tools/                            # Prebuilt binaries (ARM64 parted bundle, static qbootctl)
├── Notes/                            # Raw logs (dmesgs, dts, uart_logs, fastboot dump)
├── prepare-fedora-rootfs.sh          # Pre-boot Fedora rootfs provisioner (modules, firmware, UCM)
├── build-fedora-rootfs.sh            # Fedora sparse image builder automation
├── update_folder.sh                  # Sync repo packages -> pmbootstrap local cache
├── store_folder_in_repo.sh           # Sync pmbootstrap local cache -> repo
└── README.md                         # Port status and documentation portal
```

---

## 3. Core Workflows & Tooling

### 3.1. Synchronizing with pmbootstrap Cache

The three packaging directories (`device-xiaomi-alioth`, `firmware-xiaomi-alioth`, `linux-postmarketos-qcom-sm8250-alioth`) live inside the local `pmbootstrap` ports tree under `~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/`.

- **Push changes to pmbootstrap**:
  ```sh
  ./update_folder.sh
  ```
- **Pull changes back into repo**:
  ```sh
  ./store_folder_in_repo.sh
  ```

*Rule: Always run `./update_folder.sh` before running `pmbootstrap` build/checksum commands, and `./store_folder_in_repo.sh` after updating anything in the cache.*

### 3.2. Updating Checksums and Building

When modifying files or adding patches in any package directory:

```sh
# 1. Push changes to pmbootstrap cache
./update_folder.sh

# 2. Re-generate package checksums
pmbootstrap checksum linux-postmarketos-qcom-sm8250-alioth
# or: pmbootstrap checksum device-xiaomi-alioth
# or: pmbootstrap checksum firmware-xiaomi-alioth

# 3. Pull updated APKBUILD checksums back into repo
./store_folder_in_repo.sh

# 4. Build packages
pmbootstrap build firmware-xiaomi-alioth
pmbootstrap build --lax linux-postmarketos-qcom-sm8250-alioth
pmbootstrap build device-xiaomi-alioth
```

### 3.3. Fedora Rootfs Provisioning

When preparing Fedora rootfs for direct boot on userdata:

```sh
# Mount loopback root subvolume
sudo mkdir -p /mnt/fedora
sudo mount -o subvol=root /dev/loopXp3 /mnt/fedora

# Inject kernel modules, firmware, UCM2 profiles, modem services, ALSA state
sudo ./prepare-fedora-rootfs.sh /mnt/fedora

# Sync and convert to sparse image
sudo umount /mnt/fedora
img2simg /dev/loopXp3 fedora-rootfs.simg
```

---

## 4. Key Architectural Constraints & Gotchas

1. **No EFI / ZBOOT**:
   - `CONFIG_EFI_ZBOOT` **must be `n`**. Alioth bootloader does not implement EFI; kernel decompression fails if ZBOOT is enabled.
2. **Virtual Addressing**:
   - Alioth Cortex-A77/A55 cores require `CONFIG_ARM64_VA_BITS=48` and `CONFIG_PGTABLE_LEVELS=4` (no Large Virtual Addressing / LVA).
3. **Display & Touchscreen**:
   - Mainline drivers for Samsung AMS667XX01 panel (`CONFIG_DRM_PANEL_SAMSUNG_AMS667XX01=y`), SPI bus (`CONFIG_SPI_QCOM_GENI=y`), and FocalTech FT8756 touchscreen (`CONFIG_TOUCHSCREEN_FT8756=y`) must remain built-in (`=y`).
4. **Modem (SDX55)**:
   - SDX55 modem uses PCIe/MHI bus. Requires `mhi_bus`, `mhi_pci_generic`, `mhi_net`, `mhi_wwan_ctrl`, `qrtr`, `rmnet` drivers and userspace helpers (`tqftpserv`, modem firmware extractor). See `Notes/006-5g-modem-bringup-summary.md` and `Notes/007-modem-and-wifi-bringup-findings-draft.md`.
5. **Binary Artifacts**:
   - Never commit `.img` or `.simg` files. Verify `git status` before committing.
6. **APKBUILD Versioning**:
   - Increment `pkgrel` whenever changing patches or packaging logic without changing upstream `pkgver`.
