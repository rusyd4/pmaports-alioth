# User Configuration & Daily Usage Guide

Panduan penggunaan harian, konfigurasi hardware, audio, jaringan seluler, dan switching OS pada Xiaomi Poco F3 (`alioth`).

---

## 1. Konfigurasi Audio CS35L41

Amplifier speaker Cirrus Logic CS35L41 memiliki gain hardware konservatif secara default di ALSA:

### Meningkatkan Volume Speaker
1. Di terminal smartphone, jalankan mixer:
   ```sh
   alsamixer
   ```
2. Tekan **F6** lalu pilih kartu suara Qualcomm (sm8250).
3. Naikkan slider berikut ke level maksimum:
   - `RCV Analog PCM Volume`
   - `LCV Analog PCM Volume`
   - `RCV Digital PCM Volume`
   - `LCV Digital PCM Volume`
4. Simpan status mixer agar permanen:
   ```sh
   sudo alsactl store
   ```
5. Atau di **KDE Sound Settings**, aktifkan opsi **"Raise maximum volume" / "Allow volume over 100%"**.

---

## 2. Jaringan Seluler 5G & Modem SDX55

Modem Qualcomm SDX55 terhubung via PCIe dan diatur oleh layanan `alioth-modem`, `tqftpserv`, dan `alioth-modem-firmware`.

### Status Modem
Cek deteksi modem di ModemManager:
```sh
mmcli -L
mmcli -m 0
```

### Mengganti Slot SIM Aktif
Poco F3 mendukung dual SIM fisik. Mainline kernel mengarahkan data seluler ke satu modem aktif:

- **Via GUI**:
  Buka menu aplikasi Plasma Mobile → pilih ikon **"Ganti ke SIM 1"** atau **"Ganti ke SIM 2"**.
- **Via Terminal**:
  ```sh
  # Aktifkan SIM 1
  sudo alioth-switch-sim 1

  # Aktifkan SIM 2
  sudo alioth-switch-sim 2
  ```

---

## 3. Wi-Fi & Bluetooth

- **Wi-Fi**:
  Gunakan GUI Plasma Mobile atau tool terminal:
  ```sh
  nmtui
  # atau
  nmcli dev wifi connect "NAMA_SSID" password "PASSWORD_WIFI"
  ```
- **Bluetooth**:
  Layanan `alioth-bluetooth.service` berjalan otomatis saat boot dan menginisialisasi controller via script `/usr/local/bin/alioth-bluetooth-init.sh`. Cek status:
  ```sh
  bluetoothctl show
  ```

---

## 4. Akses SSH & Remote Shell

Image Fedora yang disiapkan melalui `prepare-fedora-rootfs.sh` otomatis mengaktifkan SSH server:
- **Port**: 22
- **User**: `root`
- **Default password**: `fedora`
- **SSH Key**: Public key host PC (`~/.ssh/id_*.pub`) otomatis disuntikkan ke `/root/.ssh/authorized_keys`.

Hubungkan smartphone ke PC via kabel USB atau jaringan Wi-Fi lokal:
```sh
ssh root@172.16.42.1
# atau via IP Wi-Fi
ssh root@192.168.x.x
```

---

## 5. Update Sistem (DNF Safety)

Skrip penyedia Fedora otomatis memblokir paket kernel dan ModemManager dari DNF di `/etc/dnf/dnf.conf` (`excludepkgs=kernel* ModemManager*`). Hal ini krusial agar `dnf update` tidak menimpa kernel mainline kustom alioth dengan kernel generik Fedora aarch64.
