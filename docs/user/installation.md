# Installation Guide: Xiaomi Poco F3 (alioth)

Mainline Linux installation guide (postmarketOS & Fedora ARM64) for the Xiaomi Poco F3 (`alioth`).

---

## 1. Prerequisites (Host PC)

Ensure your host PC has the required tools installed:
```sh
# Arch Linux
sudo pacman -S android-tools btrfs-progs

# Debian / Ubuntu / Fedora
sudo apt install android-tools-adb android-tools-fastboot btrfs-progs
# or: sudo dnf install android-tools btrfs-progs
```

Phone requirements:
- Bootloader unlocked.
- Reliable USB-C cable.
- Custom recovery (OrangeFox or TWRP) for dual boot installation.

---

## 2. Installation Options

1. **[Single Boot postmarketOS](#option-a-single-boot-postmarketos)**: Minimal / Plasma Mobile Alpine-based environment.
2. **[Single Boot Fedora ARM64](#option-b-single-boot-fedora-arm64)**: Full Fedora KDE Mobile across the entire `userdata` partition.
3. **[Dual Boot (AOSP + Fedora)](#option-c-dual-boot-aosp--fedora)**: Android on Slot A and Fedora Linux on Slot B.

---

## Option A: Single Boot postmarketOS

Use `pmbootstrap` to build packages and flash directly to the device:

```sh
# 1. Boot phone into Fastboot mode (Power + Volume Down)

# 2. Erase OEM DTBO on slot B to prevent device tree conflicts
fastboot erase dtbo_b

# 3. Flash rootfs and kernel
pmbootstrap flasher flash_rootfs --partition userdata
pmbootstrap flasher flash_kernel --partition boot_b

# 4. Activate slot B and reboot
fastboot set_active b
fastboot reboot
```

---

## Option B: Single Boot Fedora ARM64

### 1. Prepare Fedora Rootfs Sparse Image
Download a raw Fedora KDE Mobile disk image (`Fedora-KDE-Mobile-Disk-*.raw.xz`), then build the prepared sparse image using the automation script:
```sh
sudo ./build-fedora-rootfs.sh /path/to/Fedora-KDE-Mobile-Disk-*.raw fedora-rootfs.simg
```
*This script automatically injects kernel modules, non-free firmware, ALSA UCM2 audio profiles, cellular configs, modem services, and the `qbootctl` utility into `/usr/local/bin`.*

### 2. Repack Boot Image for `userdata`
The initramfs must mount the root subvolume on `userdata`:
```sh
mkdir -p /tmp/boot_unpack
unpack_bootimg \
  --boot_img ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/boot/boot.img \
  --out /tmp/boot_unpack

mkbootimg \
  --header_version 0 \
  --kernel /tmp/boot_unpack/kernel \
  --ramdisk /tmp/boot_unpack/ramdisk \
  --pagesize 0x00001000 \
  --base 0x00000000 \
  --kernel_offset 0x00008000 \
  --ramdisk_offset 0x01000000 \
  --second_offset 0x00f00000 \
  --tags_offset 0x00000100 \
  --board '' \
  --cmdline 'quiet splash plymouth.ignore-serial-consoles plymouth.prefer-fbcon pmos_root=/dev/disk/by-partlabel/userdata pmos_rootfsopts=subvol=root selinux=0' \
  -o ~/boot_fedora.img

rm -rf /tmp/boot_unpack
```

### 3. Flash via Fastboot
```sh
fastboot erase dtbo_b
fastboot flash boot_b ~/boot_fedora.img
fastboot flash userdata ~/fedora-rootfs.simg
fastboot set_active b
fastboot reboot
```

---

## Option C: Dual Boot (AOSP + Fedora)

To run Android (AOSP) alongside Fedora Linux:
- The 242 GB `userdata` partition is split into two 121 GB partitions using prebuilt `tools/parted`.
- Slot A is reserved for Android AOSP.
- Slot B is reserved for Fedora Linux.

👉 **Follow the full guide in [Dual Boot Guide](dualboot.md).**

---

## Post-Installation

After your system boots up, see the **[Configuration Guide](configuration.md)** to:
- Boost Cirrus Logic CS35L41 speaker volume.
- Set up the SDX55 5G modem and switch between SIM 1 and SIM 2.
- Switch active boot slots between Android and Linux.
