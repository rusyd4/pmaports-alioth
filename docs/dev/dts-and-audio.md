# Device Tree & Audio Architecture Guide

Dokumentasi penanganan Device Tree Source (DTS), ekstraksi DTB, dan debugging subsistem audio CS35L41 pada Xiaomi Poco F3 (`alioth`).

---

## 1. Ekstraksi Device Tree Source (DTS)

Untuk memverifikasi node hardware dan pemetaan pinout terhadap kernel Android OEM:

### 1. Ekstraksi dari Image LineageOS / Android Vendor Boot
Poco F3 menggunakan partisi `vendor_boot` (Android Header Version 3):
```sh
# Ekstrak vendor_boot.img
unpack_bootimg --boot_img vendor_boot.img --out /tmp/vb_out

# Decompile dtb biner menjadi dts yang terbaca
dtc -I dtb -O dts -o alioth_vendor.dts /tmp/vb_out/dtb
```

### 2. Ekstraksi dari postmarketOS yang Berjalan
```sh
dtc -I dtb -O dts -o alioth-mainline.dts /boot/sm8250-xiaomi-alioth.dtb
```

Arsip hasil ekstraksi dts tersedia di folder `Notes/dts/`.

---

## 2. Subsistem Audio: Dual Cirrus Logic CS35L41

Alioth menggunakan dua smart amplifier hardware Cirrus Logic CS35L41 yang dikendalikan via bus I2C:
- **Earpiece / Receiver (RCV)**: I2C slave address `0x40` pada bus `&i2c3`.
- **Loudspeaker (LCV)**: I2C slave address `0x41` pada bus `&i2c3`.

### Investigasi "Mystery Buzz" saat Suspend / Resume
Pada iterasi awal porting, muncul bunyi dengung singkat ("buzz") sesaat setelah device dibangunkan dari suspend:
- Sumber masalah: Urutan power rail sequencing regulator pada DTS dan penanganan reset GPIO amplifier CS35L41 saat transisi state D3cold → D0.
- Detail catatan debugging lengkap dapat dibaca pada `Notes/001-debuggin_buzz.md`.

---

## 3. Profil ALSA Use Case Manager (UCM2)

Berkas UCM2 diletakkan di `device-xiaomi-alioth/alsa-ucm-conf/`:
- `alioth.conf`: Pendefinisian sound card name dan routing case.
- `HiFi.conf`: Pengaturan volume mixer, routing PCM, dan enabling amplifier stream.
- `asound.state`: Kalibrasi default ALSA channel volume level.
