# Installation Guide: Xiaomi Poco F3 (alioth)

Panduan instalasi mainline Linux (postmarketOS & Fedora ARM64) pada Xiaomi Poco F3 (`alioth`).

---

## 1. Persyaratan Awal (Host PC)

Pastikan host PC memiliki tools berikut:
```sh
# Arch Linux
sudo pacman -S android-tools btrfs-progs

# Debian / Ubuntu / Fedora
sudo apt install android-tools-adb android-tools-fastboot btrfs-progs
# atau: sudo dnf install android-tools btrfs-progs
```

Phone requirement:
- Bootloader ter-unlock (unlocked bootloader).
- Kabel USB-C yang stabil.
- Custom recovery (OrangeFox / TWRP) untuk instalasi dual boot.

---

## 2. Pilihan Instalasi

1. **[Single Boot postmarketOS](#option-a-single-boot-postmarketos)**: Alpine-based minimal / Plasma Mobile.
2. **[Single Boot Fedora ARM64](#option-b-single-boot-fedora-arm64)**: Fedora KDE Mobile pada seluruh partisi `userdata`.
3. **[Dual Boot (AOSP + Fedora)](#option-c-dual-boot-aosp--fedora)**: Android di Slot A dan Fedora Linux di Slot B.

---

## Option A: Single Boot postmarketOS

Gunakan `pmbootstrap` untuk build dan flashing langsung ke smartphone:

```sh
# 1. Masuk ke mode Fastboot (Power + Volume Down)

# 2. Hapus OEM DTBO slot B untuk menghindari konflik device tree
fastboot erase dtbo_b

# 3. Flash rootfs dan kernel
pmbootstrap flasher flash_rootfs --partition userdata
pmbootstrap flasher flash_kernel --partition boot_b

# 4. Aktifkan slot B dan reboot
fastboot set_active b
fastboot reboot
```

---

## Option B: Single Boot Fedora ARM64

### 1. Siapkan Rootfs Fedora
Download image Fedora KDE Mobile disk (`Fedora-KDE-Mobile-Disk-*.raw.xz`), lalu build sparse image menggunakan skrip otomatisasi:
```sh
sudo ./build-fedora-rootfs.sh /path/to/Fedora-KDE-Mobile-Disk-*.raw fedora-rootfs.simg
```
*Skrip ini otomatis menginjeksi kernel modules, firmware, profil ALSA UCM2, konfigurasi cellular, modem services, dan utility `qbootctl` ke `/usr/local/bin`.*

### 2. Repack Boot Image untuk `userdata`
Initramfs perlu diarahkan ke partisi `userdata`:
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

Untuk menjalankan Android (AOSP) berdampingan dengan Fedora Linux:
- Partisi `userdata` (242 GB) dibagi menjadi dua partisi 121 GB menggunakan prebuilt `tools/parted`.
- Slot A digunakan untuk Android AOSP.
- Slot B digunakan untuk Fedora Linux.

👉 **Ikuti panduan lengkap di [Dual Boot Guide](dualboot.md).**

---

## Pasca Instalasi

Setelah sistem menyala, buka **[Configuration Guide](configuration.md)** untuk:
- Mengaktifkan volume audio CS35L41.
- Setup modem 5G SDX55 dan ganti SIM 1 / 2.
- Mengganti slot boot antara Android dan Linux.
