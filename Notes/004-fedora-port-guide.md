# Booting Fedora on Xiaomi Poco F3 (alioth)

Self-contained guide to install and boot Fedora ARM64 (KDE Mobile / Plasma) on the Xiaomi Poco F3 (`alioth`).

---

## 1. Prerequisites (Host)

On your Arch Linux host:

```sh
sudo pacman -S android-tools btrfs-progs
```

---

## 2. Kernel Compilation (pmbootstrap)

Mainline drivers for the display panel, SPI bus, and touchscreen must be compiled as built-ins (`=y`):

1. **Kernel configuration** (`linux-postmarketos-qcom-sm8250-alioth/config-postmarketos-qcom-sm8250-alioth.aarch64`):
   ```kconfig
   CONFIG_SPI_QCOM_GENI=y
   CONFIG_TOUCHSCREEN_FT8756=y
   CONFIG_DRM_PANEL_SAMSUNG_AMS667XX01=y
   ```

2. **Build kernel packages**:
   ```sh
   pmbootstrap build firmware-xiaomi-alioth
   pmbootstrap build linux-postmarketos-qcom-sm8250-alioth
   pmbootstrap build device-xiaomi-alioth
   ```

---

## 3. Prepare Fedora Rootfs

1. **Extract and mount the raw Fedora image**:
   ```sh
   unxz Fedora-KDE-Mobile-Disk-*.raw.xz
   sudo losetup -Pf Fedora-KDE-Mobile-Disk-*.raw
   sudo mkdir -p /mnt/fedora
   sudo mount -o subvol=root /dev/loop0p3 /mnt/fedora
   ```

2. **Copy kernel modules and device firmware**:
   ```sh
   sudo cp -r ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/lib/modules/* \
     /mnt/fedora/usr/lib/modules/

   sudo cp -r ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/lib/firmware/* \
     /mnt/fedora/usr/lib/firmware/

   # ALSA Audio UCM profiles
   sudo mkdir -p /mnt/fedora/usr/share/alsa/ucm2/Xiaomi/alioth /mnt/fedora/usr/share/alsa/ucm2/conf.d/sm8250
   sudo cp ~/pmaports-alioth/device-xiaomi-alioth/alsa-ucm-conf/*.conf \
     /mnt/fedora/usr/share/alsa/ucm2/Xiaomi/alioth/
   sudo ln -sf ../../Xiaomi/alioth/alioth.conf \
     /mnt/fedora/usr/share/alsa/ucm2/conf.d/sm8250/xiaomi-alioth.conf
   ```

3. **Disable unused `/boot` mounts in `/etc/fstab`**:
   *(Fedora raw images mount `/boot` and `/boot/efi` by UUID. Since we only flash the root filesystem to userdata, comment them out to prevent a 90s systemd timeout / emergency mode)*:
   ```sh
   sudo sed -i '/\/boot/s/^/#/' /mnt/fedora/etc/fstab
   ```

4. **Unlock root account**:
   *(Fedora raw images default to a locked root account `root:!`, which blocks emergency login)*:
   ```sh
   HASH=$(openssl passwd -6 fedora)
   sudo sed -i "s|^root:!:[^:]*|root:${HASH}:20565|" /mnt/fedora/etc/shadow
   ```

5. **Convert to Android Sparse image**:
   ```sh
   sudo sync
   sudo umount /mnt/fedora
   sudo img2simg /dev/loop0p3 ~/fedora-rootfs.simg
   sudo losetup -d /dev/loop0
   ```

---

## 4. Generate the Boot Image (`boot_fedora.img`)

Because `pmbootstrap` sets cmdline arguments aimed at Alpine's UUID, repack the initramfs kernel using `mkbootimg` to mount Fedora's Btrfs subvolume directly:

```sh
mkdir -p /tmp/boot_unpack
unpack_bootimg \
  --boot_img ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/boot/boot.img \
  --out /tmp/boot_unpack

# For standalone Fedora on userdata:
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

---

## 5. Flash via Fastboot

Reboot phone to Fastboot mode (Power + Volume Down):

```sh
# 1. Erase OEM DTBO (avoids device tree conflicts)
fastboot erase dtbo_b

# 2. Flash repacked boot image to slot B
fastboot flash boot_b ~/boot_fedora.img

# 3. Flash Fedora rootfs to userdata
fastboot flash userdata ~/fedora-rootfs.simg

# 4. Activate slot B and reboot
fastboot set_active b
fastboot reboot
```
