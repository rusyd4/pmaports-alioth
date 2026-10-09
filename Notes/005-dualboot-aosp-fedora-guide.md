# Dual Boot Guide: AOSP (Slot A) & Fedora (Slot B) on Poco F3 (alioth)

Complete, self-contained guide to dual boot **AOSP (Android)** and **Fedora (Linux)** on a 256GB Xiaomi Poco F3 using A/B slots and a 50/50 UFS storage split.

---

## 1. Partition Architecture

| Component | Slot A (Android / AOSP) | Slot B (Fedora Linux) |
| :--- | :--- | :--- |
| **Boot partition** | `boot_a` (Android kernel) | `boot_b` (`boot_fedora.img` mainline) |
| **DTBO** | `dtbo_a` (OEM DTBO) | `dtbo_b` (erased / empty) |
| **System** | Dynamic partitions in `super` | Rootfs on dedicated `linux` partition |
| **Storage / Data** | `userdata` (121 GB, F2FS, encrypted) | `linux` (121 GB, Btrfs, unencrypted) |

---

## 2. Requirements

* Host PC with `android-tools`, `multipath-tools`, and `btrfs-progs` installed.
* Custom recovery (OrangeFox or TWRP) for Poco F3.
* A working `fedora-rootfs.simg` prepared per [`004-fedora-port-guide.md`](004-fedora-port-guide.md).
* Full backup of your phone data (repartitioning wipes existing Android userdata).

---

## 3. Step 1: Repartition UFS Storage (`sda`)

On 256GB Poco F3 devices, `/dev/block/sda` has `userdata` as partition **35** (starting at 11.4 GB and ending at 253 GB, totaling ~242 GB). We split it 50/50 into two 121 GB partitions.

1. **Boot into OrangeFox / TWRP:**
   ```sh
   fastboot boot OrangeFox-alioth.img
   ```

2. **Push the ARM64 `parted` bundle to the phone:**
   *(Android recovery images do not include an ARM64 parted binary. We bundle parted with its musl dynamic loader)*:
   ```sh
   # From your PC with the pmaports buildroot:
   mkdir -p /tmp/parted-arm64/lib /tmp/parted-arm64/bin
   sudo cp ~/.local/var/pmbootstrap/chroot_buildroot_aarch64/usr/bin/parted /tmp/parted-arm64/bin/
   sudo cp ~/.local/var/pmbootstrap/chroot_buildroot_aarch64/lib/ld-musl-aarch64.so.1 /tmp/parted-arm64/lib/
   sudo cp ~/.local/var/pmbootstrap/chroot_buildroot_aarch64/lib/libparted.so* /tmp/parted-arm64/lib/
   sudo cp ~/.local/var/pmbootstrap/chroot_buildroot_aarch64/lib/libreadline.so* /tmp/parted-arm64/lib/
   sudo cp ~/.local/var/pmbootstrap/chroot_buildroot_aarch64/lib/libuuid.so* /tmp/parted-arm64/lib/
   sudo cp ~/.local/var/pmbootstrap/chroot_buildroot_aarch64/lib/libncursesw.so* /tmp/parted-arm64/lib/
   sudo cp ~/.local/var/pmbootstrap/chroot_buildroot_aarch64/lib/libdevmapper.so* /tmp/parted-arm64/lib/
   sudo cp ~/.local/var/pmbootstrap/chroot_buildroot_aarch64/lib/libblkid.so* /tmp/parted-arm64/lib/
   sudo cp ~/.local/var/pmbootstrap/chroot_buildroot_aarch64/usr/lib/libeconf.so* /tmp/parted-arm64/lib/

   cat << 'EOF' > /tmp/parted-arm64/parted
   #!/system/bin/sh
   exec /tmp/parted-arm64/lib/ld-musl-aarch64.so.1 --library-path /tmp/parted-arm64/lib /tmp/parted-arm64/bin/parted "$@"
   EOF
   chmod +x /tmp/parted-arm64/parted

   adb push /tmp/parted-arm64 /tmp/
   adb shell "chmod +x /tmp/parted-arm64/parted /tmp/parted-arm64/bin/parted /tmp/parted-arm64/lib/ld-musl-aarch64.so.1"
   ```

3. **In `adb shell`, split partition 35:**
   ```sh
   adb shell
   cd /tmp/parted-arm64

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
   * Go to **Wipe → Format Data** → type **`yes`**.
   * This prepares partition 35 for Android encryption.

---

## 4. Step 2: Install AOSP on Slot A

1. In recovery or fastboot, activate slot A:
   ```sh
   fastboot set_active a
   ```
2. Flash your AOSP ROM (LineageOS, PixelOS, crDroid, etc.) per standard installation.
3. Boot into Android once to complete first-time setup and initialize encrypted user storage on partition 35.

---

## 5. Step 3: Install Fedora on Slot B

1. **Repack `boot.img` for the dedicated `linux` partition:**
   *(Run this on your PC to point initramfs directly to `/dev/disk/by-partlabel/linux`)*:
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
     -o ~/boot_fedora_dualboot.img

   rm -rf /tmp/boot_unpack
   ```

2. **Reboot phone to Fastboot mode (Power + Volume Down).**

3. **Flash Fedora kernel to Slot B:**
   ```sh
   fastboot erase dtbo_b
   fastboot flash boot_b ~/boot_fedora_dualboot.img
   ```

4. **Flash Fedora rootfs directly to partition 36 (`linux`):**
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
