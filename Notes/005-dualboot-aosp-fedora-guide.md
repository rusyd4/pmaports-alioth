# Dual Boot Guide: AOSP (Slot A) & Fedora (Slot B) on Poco F3 (alioth)

This guide details how to dual boot **AOSP (Android)** and **Fedora (Linux)** on a 256GB Xiaomi Poco F3 using A/B slots and a 50/50 partitioned UFS storage layout.

---

## 1. Architecture Overview

| Component | Slot A (Android / AOSP) | Slot B (Fedora Linux) |
| :--- | :--- | :--- |
| **Boot partition** | `boot_a` (Android kernel) | `boot_b` (Mainline kernel + initramfs) |
| **DTBO** | `dtbo_a` (OEM DTBO) | `dtbo_b` (erased / empty) |
| **System** | Dynamic partitions inside `super` | Rootfs on dedicated `linux` partition |
| **Storage / Data** | `userdata` (121 GB, F2FS, encrypted) | `linux` (121 GB, Btrfs, unencrypted) |

---

## 2. Requirements

* Computer with `adb` and `fastboot` (`android-tools`).
* Custom recovery for alioth booted via fastboot (e.g. OrangeFox / TWRP).
* ARM64 `parted` utility (OrangeFox does not include a static parted binary; push a musl-based ARM64 parted bundle to `/tmp/parted`).
* Full backup of your device (repartitioning wipes Android userdata).

---

## 3. Step 1: Repartition UFS Storage (`sda`)

On 256GB Poco F3 devices, `/dev/block/sda` has `userdata` as partition **35** (starting at 11.4 GB and ending at 253 GB, totaling ~242 GB). We split it 50/50 into two 121 GB partitions.

1. **Boot into OrangeFox / TWRP:**
   ```sh
   fastboot boot OrangeFox-alioth.img
   ```

2. **Open ADB Shell:**
   ```sh
   adb shell
   ```

3. **In `adb shell`, split partition 35:**
   ```sh
   cd /tmp

   # 1. Remove existing 242 GB userdata partition
   ./parted /dev/block/sda rm 35
   # If prompted with "Ignore/Cancel?", enter: i

   # 2. Re-create userdata for Android (11.4GB to 132GB = 121 GB)
   ./parted /dev/block/sda mkpart userdata ext4 11.4GB 132GB

   # 3. Create dedicated linux partition for Fedora (132GB to 253GB = 121 GB)
   ./parted /dev/block/sda mkpart linux btrfs 132GB 253GB

   # 4. Verify partition table
   ./parted /dev/block/sda print
   ```

   Result layout:
   ```text
   Number  Start   End     Size    File system  Name             Flags
   ...
   35      11.4GB  132GB   121GB   ext4         userdata
   36      132GB   253GB   121GB                linux
   ```

4. **Reboot recovery to reload kernel partition table:**
   ```sh
   reboot recovery
   ```

5. **Format `userdata` for Android:**
   Inside OrangeFox / TWRP GUI:
   * Go to **Wipe → Format Data** → type **`yes`**.
   * This prepares partition 35 with Android encryption metadata.

---

## 4. Step 2: Install AOSP on Slot A

1. In recovery or fastboot, activate slot A:
   ```sh
   fastboot set_active a
   ```
2. Flash your AOSP ROM (LineageOS, PixelOS, crDroid, etc.) per standard instructions.
3. Boot into Android once to complete first-time setup and initialize encrypted user storage on partition 35.

---

## 5. Step 3: Install Fedora on Slot B

1. **Reboot phone to Fastboot mode (Power + Volume Down).**

2. **Configure Fedora to mount the new `linux` partition:**
   In `device-xiaomi-alioth/deviceinfo`, ensure `deviceinfo_kernel_cmdline` points to `linux`:
   ```sh
   deviceinfo_kernel_cmdline="pmos_root=/dev/disk/by-partlabel/linux pmos_rootfsopts=subvol=root selinux=0"
   ```

3. **Build the boot image with pmbootstrap:**
   ```sh
   pmbootstrap build device-xiaomi-alioth
   ```

4. **Flash Fedora kernel to Slot B:**
   ```sh
   fastboot erase dtbo_b
   fastboot flash boot_b ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/boot/boot.img
   ```

5. **Flash Fedora rootfs directly to the `linux` partition:**
   ```sh
   fastboot flash linux ~/fedora-rootfs.simg
   ```

---

## 6. Switching OS at Any Time

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
Using root in Termux / shell:
```sh
su
bootctl set-active-boot-slot 1
reboot
```
*(Slot 0 = A, Slot 1 = B)*, or install the **BootControl** app from F-Droid.

### Option C: Switching from inside Fedora
In a terminal:
```sh
sudo qbootctl -s a
sudo reboot
```
*(Sets slot A active and reboots into Android).*
