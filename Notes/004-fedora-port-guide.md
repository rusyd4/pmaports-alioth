# Booting Fedora on Xiaomi Poco F3 (alioth)

Minimal guide to run Fedora ARM64 (KDE Mobile / Plasma) on the Xiaomi Poco F3 (alioth).

---

## 1. Prerequisites

On your Arch Linux host:

```sh
sudo pacman -S android-tools btrfs-progs
```

---

## 2. Kernel & Device Configuration

Ensure drivers are built into the kernel and cmdline points directly to `userdata`:

1. **Kernel config** (`linux-postmarketos-qcom-sm8250-alioth/config-postmarketos-qcom-sm8250-alioth.aarch64`):
   ```kconfig
   CONFIG_SPI_QCOM_GENI=y
   CONFIG_TOUCHSCREEN_FT8756=y
   CONFIG_DRM_PANEL_SAMSUNG_AMS667XX01=y
   ```

2. **Device info** (`device-xiaomi-alioth/deviceinfo`):
   ```sh
   deviceinfo_kernel_cmdline="pmos_root=/dev/disk/by-partlabel/userdata pmos_rootfsopts=subvol=root selinux=0"
   ```

3. **Build kernel & boot image**:
   ```sh
   pmbootstrap build firmware-xiaomi-alioth
   pmbootstrap build linux-postmarketos-qcom-sm8250-alioth
   pmbootstrap build device-xiaomi-alioth
   ```

Generated `boot.img` is in `~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/boot/boot.img`.

---

## 3. Prepare Fedora Rootfs

1. **Extract & Mount Fedora raw image**:
   ```sh
   unxz Fedora-KDE-Mobile-Disk-*.raw.xz
   sudo losetup -Pf Fedora-KDE-Mobile-Disk-*.raw
   sudo mkdir -p /mnt/fedora
   sudo mount -o subvol=root /dev/loop0p3 /mnt/fedora
   ```

2. **Copy Kernel Modules & Firmware**:
   ```sh
   sudo cp -r ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/lib/modules/* \
     /mnt/fedora/usr/lib/modules/

   sudo cp -r ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/lib/firmware/* \
     /mnt/fedora/usr/lib/firmware/

   # Audio UCM profiles
   sudo mkdir -p /mnt/fedora/usr/share/alsa/ucm2/Xiaomi/alioth /mnt/fedora/usr/share/alsa/ucm2/conf.d/sm8250
   sudo cp ~/pmaports-alioth/device-xiaomi-alioth/alsa-ucm-conf/*.conf \
     /mnt/fedora/usr/share/alsa/ucm2/Xiaomi/alioth/
   sudo ln -sf ../../Xiaomi/alioth/alioth.conf \
     /mnt/fedora/usr/share/alsa/ucm2/conf.d/sm8250/xiaomi-alioth.conf
   ```

3. **Fix `/etc/fstab`**:
   Disable partitions that are not flashed to prevent systemd mount timeouts:
   ```sh
   sudo sed -i '/\/boot/s/^/#/' /mnt/fedora/etc/fstab
   ```

4. **Convert to Sparse Image**:
   ```sh
   sudo sync
   sudo umount /mnt/fedora
   sudo img2simg /dev/loop0p3 ~/fedora-rootfs.simg
   sudo losetup -d /dev/loop0
   ```

---

## 4. Flash to Device

Reboot phone to fastboot mode (Power + Volume Down):

```sh
# 1. Erase OEM DTBO (prevents mainline DTB conflicts)
fastboot erase dtbo_b

# 2. Flash kernel to slot B
fastboot flash boot_b ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/boot/boot.img

# 3. Flash Fedora rootfs to userdata
fastboot flash userdata ~/fedora-rootfs.simg

# 4. Activate slot B and reboot
fastboot set_active b
fastboot reboot
```
