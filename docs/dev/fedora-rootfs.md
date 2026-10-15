# Fedora Rootfs Automation & Provisioning Guide

Dokumentasi skrip otomatisasi penyiapan rootfs Fedora ARM64 (`prepare-fedora-rootfs.sh` dan `build-fedora-rootfs.sh`) untuk Xiaomi Poco F3.

---

## 1. Alur Kerja Otomatisasi

Untuk menjalankan Fedora secara langsung pada Poco F3, image mentah generic ARM64 (`Fedora-KDE-Mobile-Disk-*.raw`) harus disuntikkan konfigurasi driver dan hardware sebelum di-flash ke UFS.

### Skrip Utama:
1. **`build-fedora-rootfs.sh [raw_image] [out_simg]`**:
   - Menghubungkan raw disk image ke loop device (`losetup -Pf`).
   - Melakukan mount subvolume Btrfs root (`-o subvol=root /dev/loopXp3 /mnt/fedora`).
   - Menjalankan `prepare-fedora-rootfs.sh /mnt/fedora`.
   - Mengonversi subvolume yang telah dipatch menjadi Android Sparse Image (`img2simg`).
2. **`prepare-fedora-rootfs.sh [rootfs_mount_dir]`**:
   - Menjalankan 8 tahap provisioning hardware secara langsung ke dalam rootfs target.

---

## 2. Rincian 8 Tahap Provisioning

1. **Kernel Modules & Firmware**:
   - Mengekstrak modul kernel dari paket APK pmbootstrap terbaru (`linux-postmarketos-qcom-sm8250-alioth-*.apk`).
   - Menyalin berkas firmware non-free dari pmbootstrap (`/lib/firmware`).
   - Menjalankan `depmod -a -b ${ROOTFS}` untuk semua versi kernel yang terdeteksi.

2. **Audio UCM2 & ALSA State**:
   - Menyalin profil `alioth.conf` dan `HiFi.conf` ke `/usr/share/alsa/ucm2/Xiaomi/alioth/`.
   - Membuat symlink otomatis untuk variasi nama driver soundcard SM8250.
   - Menyuntikkan `asound.state` yang telah terkalibrasi ke `/var/lib/alsa/asound.state`.

3. **Bluetooth Controller**:
   - Menyalin script inisialisasi `/usr/local/bin/alioth-bluetooth-init.sh`.
   - Mengaktifkan unit systemd `alioth-bluetooth.service`.
   - Mengonfigurasi modul autoload `bluetooth.conf`.

4. **Network, Sensor, & Plasma Tweaks**:
   - Menonaktifkan Wi-Fi power save via `/etc/NetworkManager/conf.d/wifi-powersave.conf`.
   - Menyalin udev rule sensor SSC (`81-libssc-xiaomi-alioth.rules`).
   - Menonaktifkan dialog pop-up KWallet di Plasma Mobile (`kwalletrc`).
   - Menyiapkan profil koneksi seluler otomatis (`cellular.nmconnection`).

5. **Modem Daemons, Helper, & SIM Switching**:
   - Memasang script Python Sahara & EFS (`sahara_srv.py`, `efs_srv.py`, `data_up.py`).
   - Memasang prebuilt binary daemon `tqftpserv` dan `qbootctl`.
   - Menyiapkan shortcut aplikasi desktop Plasma Mobile untuk switch SIM 1 dan SIM 2.
   - Mengaktifkan layanan `alioth-modem.service`, `tqftpserv.service`, dan `alioth-modem-firmware.service`.

6. **Kredensial Root & Akses SSH**:
   - Mengatur password default user `root` menjadi `fedora`.
   - Menginjeksi SSH public keys host (`~/.ssh/id_*.pub`) ke `/root/.ssh/authorized_keys`.
   - Menghasilkan host key SSH (rsa, ecdsa, ed25519) dan mengaktifkan service `sshd`.
   - Menginstal custom RPM (ModemManager dengan patch alioth) jika tersedia di folder `rpms/`.

7. **Patching `/etc/fstab`**:
   - Mengomentari entri `/boot` bawaan Fedora agar tidak bentrok dengan partisi Android boot A/B.

8. **Proteksi Paket di DNF**:
   - Menambahkan aturan `excludepkgs=kernel* ModemManager*` ke `/etc/dnf/dnf.conf` agar update sistem tidak menimpa kernel custom alioth.
