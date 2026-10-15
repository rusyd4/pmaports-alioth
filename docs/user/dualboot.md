# Dual Boot Guide: AOSP (Slot A) & Fedora (Slot B)

Panduan lengkap instalasi Dual Boot **Android AOSP** dan **Fedora Linux** pada Xiaomi Poco F3 (256GB UFS) dengan pembagian storage 50/50.

---

## 1. Arsitektur Partisi

| Komponen | Slot A (Android / AOSP) | Slot B (Fedora Linux) |
| :--- | :--- | :--- |
| **Boot Kernel** | `boot_a` (Kernel Android OEM/AOSP) | `boot_b` (Mainline Linux `boot_fedora_dualboot.img`) |
| **DTBO** | `dtbo_a` (OEM DTBO) | `dtbo_b` (dihapus / kosong) |
| **System** | Partisi dinamis di `super` | Rootfs di partisi dedicated `linux` |
| **Data Storage** | `userdata` (Partisi 35: 121 GB, F2FS/ext4 terenkripsi) | `linux` (Partisi 36: 121 GB, Btrfs tidak terenkripsi) |

---

## 2. Langkah 1: Repartisi UFS (`sda`) dengan `tools/parted`

Partisi asli `userdata` pada 256GB Poco F3 adalah partisi nomor 35 (mulai 11.4 GB s.d. 253 GB, ~242 GB). Kita membaginya menjadi 2 partisi masing-masing 121 GB.

1. **Boot ke Custom Recovery (OrangeFox / TWRP):**
   ```sh
   fastboot boot OrangeFox-alioth.img
   ```

2. **Push prebuilt `parted` bundle ke smartphone:**
   *(Repo ini menyediakan prebuilt ARM64 parted lengkap beserta loader musl di folder `tools/parted/`)*:
   ```sh
   adb push tools/parted /tmp/
   adb shell "chmod +x /tmp/parted/parted /tmp/parted/bin/parted /tmp/parted/lib/ld-musl-aarch64.so.1"
   ```

3. **Jalankan Partisi di `adb shell`:**
   ```sh
   adb shell
   cd /tmp/parted

   # 1. Hapus partisi userdata lama
   ./parted /dev/block/sda rm 35
   # Jika muncul prompt "Ignore/Cancel?", ketik: i lalu Enter

   # 2. Buat partisi userdata untuk Android (11.4GB ke 132GB = 121 GB)
   ./parted /dev/block/sda mkpart userdata ext4 11.4GB 132GB

   # 3. Buat partisi dedicated linux untuk Fedora (132GB ke 253GB = 121 GB)
   ./parted /dev/block/sda mkpart linux btrfs 132GB 253GB

   # 4. Cek hasil tabel partisi
   ./parted /dev/block/sda print
   exit
   ```

   Verifikasi baris akhir tabel partisi:
   ```text
   Number  Start   End     Size    File system  Name             Flags
   ...
   35      11.4GB  132GB   121GB   ext4         userdata
   36      132GB   253GB   121GB                linux
   ```

4. **Reboot recovery agar kernel memuat ulang tabel partisi:**
   ```sh
   adb reboot recovery
   ```

5. **Format `userdata` untuk Android:**
   Pada GUI OrangeFox / TWRP:
   - Pilih menu **Wipe → Format Data → ketik `yes`**.
   - Ini memformat partisi 35 agar siap dienkripsi oleh Android.

---

## 3. Langkah 2: Install AOSP di Slot A

1. Aktifkan Slot A:
   ```sh
   fastboot set_active a
   ```
2. Flash custom ROM AOSP pilihan Anda (LineageOS, PixelOS, crDroid, dll.) melalui recovery atau fastboot.
3. Boot ke Android minimal satu kali sampai masuk ke Home screen untuk menyelesaikan inisialisasi enkripsi storage partisi 35.

---

## 4. Langkah 3: Install Fedora di Slot B

1. **Repack `boot.img` mengarah ke partisi `linux` (`pmos_root=/dev/disk/by-partlabel/linux`):**
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

2. **Masuk ke mode Fastboot (Power + Volume Down).**

3. **Flash kernel ke Slot B & rootfs ke partisi `linux`:**
   ```sh
   fastboot erase dtbo_b
   fastboot flash boot_b ~/boot_fedora_dualboot.img
   fastboot flash linux ~/fedora-rootfs.simg
   ```

---

## 5. Langkah 4: Berpindah OS Kapan Saja

### Dari PC (Fastboot)
* **Boot Android (Slot A):**
  ```sh
  fastboot set_active a && fastboot reboot
  ```
* **Boot Fedora (Slot B):**
  ```sh
  fastboot set_active b && fastboot reboot
  ```

### Dari Dalam Android
Gunakan shell Root (Termux / ADB):
```sh
su
bootctl set-active-boot-slot 1
reboot
```
*(Slot 0 = Slot A / Android, Slot 1 = Slot B / Fedora)*, atau gunakan aplikasi **BootControl** dari F-Droid.

### Dari Dalam Fedora Linux
Buka terminal Plasma Mobile:
```sh
sudo qbootctl -s a
sudo reboot
```
*(Utility `qbootctl` telah terpasang otomatis di `/usr/local/bin/qbootctl`)*.
