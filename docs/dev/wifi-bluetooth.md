# Wi-Fi & Bluetooth Bring-Up Guide (QCA6390)

Dokumentasi bring-up chipset Qualcomm Atheros QCA6390 (Wi-Fi 6 + Bluetooth 5.1) pada Xiaomi Poco F3 (`alioth`).

---

## 1. Arsitektur Antarmuka Hardware

Chip QCA6390 terhubung ke SoC SM8250 melalui dua antarmuka fisik terpisah:
1. **Wi-Fi**: Antarmuka PCIe gen 2 via kontroler PCIe MHI (`ath11k_pci`).
2. **Bluetooth**: Jalur serial UART kecepatan tinggi (`ttyMSM1`) yang dikendalikan oleh protokol HCI Qualcomm (`hci_qcomm_init`).

---

## 2. Masalah Kritis Wi-Fi: MHI State Transitions

Pada kernel Linux mainline terdahulu, inisialisasi chip Wi-Fi QCA6390 sering mengalami timeout atau bus freeze saat berpindah status daya (Power State Transitions: M0 → M3 → M0).

### Akar Masalah:
Transisi status MHI yang terlalu agresif menyebabkan registri PCIe kehilangan clock sync sebelum firmware chip WLAN selesai dieksekusi.

### Solusi Driver:
Pembatasan transisi state MHI dan penyesuaian delay timeout pada driver `ath11k` dan subsistem `mhi_bus`. Detail implementasi terdokumentasi pada catatan commit `112dbb63c12cb6379efd5028fc68bd5c83460fea` dan patch kernel `0003-wifi-qca6390-bringup.patch`.

---

## 3. Konfigurasi Driver Wi-Fi

```kconfig
CONFIG_ATH11K=m
CONFIG_ATH11K_PCI=m
CONFIG_ATH11K_DEBUG=y
CONFIG_QRTR=m
```

### Optimasi Power Save
NetworkManager secara default mengaktifkan agresif Wi-Fi power save yang dapat menyebabkan drop koneksi berkala pada chip QCA6390. Solusi diterapkan via `/etc/NetworkManager/conf.d/wifi-powersave.conf`:
```ini
[connection]
wifi.powersave = 2
```
*(Nilai 2 = Menonaktifkan powersave untuk kestabilan koneksi maksimal).*

---

## 4. Inisialisasi Bluetooth

Layanan Bluetooth dikelola oleh `alioth-bluetooth.service` dan inisialisasi hardware `/usr/local/bin/alioth-bluetooth-init.sh`:

1. Memuat modul `hci_uart`.
2. Menghidupkan power rail RFKILL Bluetooth.
3. Menjalankan inisialisasi firmware patch RAM QCA6390 pada port UART serial:
   ```sh
   hci_qcomm_init -e -p 2 -s 3000000 /dev/ttyMSM1
   ```
4. Memulai daemon `bluetoothd` standar BlueZ.
