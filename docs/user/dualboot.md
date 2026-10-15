# Dual Boot Guide: AOSP (Slot A) & Fedora (Slot B)

Complete, self-contained guide to dual boot **Android (AOSP)** and **Fedora Linux** on a 256GB Xiaomi Poco F3 using A/B slots and a 50/50 UFS storage split.

---

## 1. Partition Architecture

| Component | Slot A (Android / AOSP) | Slot B (Fedora Linux) |
| :--- | :--- | :--- |
| **Boot Kernel** | `boot_a` (Android / AOSP kernel) | `boot_b` (Mainline Linux `boot_linux.img`) |
| **DTBO** | `dtbo_a` (OEM DTBO) | `dtbo_b` (erased / empty) |
| **System** | Dynamic partitions in `super` | Rootfs on dedicated `linux` partition |
| **Data Storage** | `userdata` (Partition 35: 121 GB, F2FS/ext4, encrypted) | `linux` (Partition 36: 121 GB, Btrfs, unencrypted) |

---

## 2. Step 1: Repartition UFS Storage (`sda`) with `tools/parted`

On 256GB Poco F3 devices, `/dev/block/sda` has `userdata` as partition **35** (starting at 11.4 GB and ending at 253 GB, totaling ~242 GB). We split it 50/50 into two 121 GB partitions.

1. **Boot into Custom Recovery (OrangeFox / TWRP):**
   ```sh
   fastboot boot OrangeFox-alioth.img
   ```

2. **Push the prebuilt ARM64 `parted` bundle to the phone:**
   *(Use the prebuilt `tools/parted/` bundle provided in this repository)*:
   ```sh
   adb push tools/parted /tmp/
   adb shell "chmod +x /tmp/parted/parted /tmp/parted/bin/parted /tmp/parted/lib/ld-musl-aarch64.so.1"
   ```

3. **In `adb shell`, split partition 35:**
   ```sh
   adb shell
   cd /tmp/parted

   # 1. Remove existing 242 GB userdata partition
   ./parted /dev/block/sda rm 35
   # When prompted with "Ignore/Cancel?", enter: i

   # 2. Re-create userdata for Android (11.4GB to 132GB = 121 GB)
   ./parted /dev/block/sda mkpart userdata ext4 11.4GB 132GB

   # 3. Create dedicated linux partition for Fedora (132GB to 253GB = 121 GB)
   ./parted /dev/block/sda mkpart linux btrfs 132GB 253GB

   # 4. Verify partition table
   ./parted /dev/block/sda print
   exit
   ```

   Verified partition table output:
   ```text
   Number  Start   End     Size    File system  Name             Flags
   ...
   35      11.4GB  132GB   121GB   ext4         userdata
   36      132GB   253GB   121GB                linux
   ```

4. **Reboot recovery to reload kernel partition table:**
   ```sh
   adb reboot recovery
   ```

5. **Format `userdata` for Android:**
   Inside OrangeFox / TWRP GUI:
   - Go to **Wipe → Format Data → type `yes`**.
   - This prepares partition 35 for Android encryption.

---

## 3. Step 2: Install AOSP on Slot A

1. In recovery or fastboot, activate Slot A:
   ```sh
   fastboot set_active a
   ```
2. Flash your AOSP ROM (LineageOS, PixelOS, crDroid, etc.) per standard installation.
3. Boot into Android once to complete first-time setup and initialize encrypted user storage on partition 35.

---

## 4. Step 3: Install Fedora on Slot B

### 1. Download Prebuilt Dual Boot Images (Recommended)
Download release assets from **[GitHub Releases](https://github.com/rusyd4/pmaports-alioth/releases)**:
* **`boot_linux.img`**: Prebuilt boot image configured with rootfs cmdline for the dedicated `linux` partition (`pmos_root=/dev/disk/by-partlabel/linux`).
* **`fedora-rootfs.simg`**: Prebuilt Fedora KDE Mobile rootfs sparse image.

### 2. Flash via Fastboot
1. Reboot phone to Fastboot mode (Power + Volume Down).
2. Flash the kernel to Slot B and rootfs to the dedicated `linux` partition:
   ```sh
   fastboot erase dtbo_b
   fastboot flash boot_b boot_linux.img
   fastboot flash linux fedora-rootfs.simg
   ```

<details>
<summary><b>🛠️ Repacking Boot Image Manually (Optional / Advanced)</b></summary>

If you want to repack `boot_linux.img` yourself from a postmarketOS `boot.img`:
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
  --cmdline 'quiet splash plymouth.ignore-serial-consoles plymouth.prefer-fbcon pmos_root=/dev/disk/by-partlabel/linux pmos_rootfsopts=subvol=root selinux=0' \
  -o ~/boot_linux.img

rm -rf /tmp/boot_unpack
```
</details>

---

## 5. Step 4: Switching Operating Systems

### Option A: Via Fastboot (from PC)
* **Boot Android:**
  ```sh
  fastboot set_active a && fastboot reboot
  ```
* **Boot Fedora:**
  ```sh
  fastboot set_active b && fastboot reboot
  ```

### Option B: Switching from inside Android
Using root shell in Termux or ADB:
```sh
su
bootctl set-active-boot-slot 1
reboot
```
*(Slot 0 = A / Android, Slot 1 = B / Fedora)*, or install the **BootControl** app from F-Droid.

### Option C: Switching from inside Fedora
In a terminal:
```sh
sudo qbootctl -s a
sudo reboot
```
*(The static `qbootctl` binary is preinstalled at `/usr/local/bin/qbootctl`)*.
