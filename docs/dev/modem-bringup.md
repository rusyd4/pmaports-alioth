# 5G Cellular Modem (Qualcomm SDX55) Bring-Up Guide

Dokumentasi arsitektur, driver, firmware, dan stack software untuk modem Qualcomm Snapdragon X55 (SDX55) pada Xiaomi Poco F3 (`alioth`).

---

## 1. Arsitektur Modem Flashless pada Alioth

Snapdragon 870 SoC tidak memiliki modem seluler internal terintegrasi. Komunikasi dengan baseband dilakukan melalui chip diskrit eksternal **Qualcomm SDX55** yang terhubung melalui antarmuka PCIe (`pcie2`).

- **Flashless Baseband**: Chip SDX55 pada alioth tidak memiliki chip penyimpanan flash onboard sendiri. Seluruh image firmware, kalibrasi NV, dan partisi EFS harus di-load dari storage UFS smartphone oleh host Linux saat boot.
- **Protokol Bus**:
  - Qualcomm MHI (Modem Host Interface) di atas PCIe.
  - QRTR (Qualcomm IPC Router) melalui antarmuka IPC-Router MHI.
  - RmNet (Qualcomm cellular network aggregation protocol) untuk transfer paket data IP.

---

## 2. Driver Kernel yang Dibutuhkan

```kconfig
CONFIG_MHI_BUS=m
CONFIG_MHI_BUS_PCI_GENERIC=m
CONFIG_MHI_NET=m
CONFIG_MHI_WWAN_CTRL=m
CONFIG_MHI_WWAN_MBIM=m
CONFIG_ETHERNET=y
CONFIG_NET_VENDOR_QUALCOMM=y
CONFIG_RMNET=m
CONFIG_QRTR=m
CONFIG_QRTR_SMD=m
CONFIG_QRTR_MHI=m
```

DTS node modem diaktifkan melalui `0002-add-modem-sdx55m-support.patch`.

---

## 3. Komponen Userspace & Layanan Systemd

Seluruh berkas integrasi berada di folder `device-xiaomi-alioth/modem-services/`:

1. **`alioth-modem-firmware.service` / `alioth-modem-firmware.sh`**:
   - Membaca partisi firmware modem dari UFS (`modemst1`, `modemst2`, `fsg`, `fsc`).
   - Menyiapkan berkas firmware baseband di `/lib/firmware/qcom/sdx55m/`.

2. **`tqftpserv.service`**:
   - Daemon TFTP userspace yang melayani request pemuatan firmware dan partisi EFS yang diminta oleh modem SDX55 via channel QRTR.
   - Prebuilt binary ARM64 disertakan di `device-xiaomi-alioth/modem-services/tqftpserv`.

3. **`alioth-modem.service`**:
   - Menjalankan helper Sahara & EFS (`sahara_srv.py`, `efs_srv.py`, `data_up.py`).
   - Menginisialisasi interface jaringan `rmnet_mhi0` dan mapping port QRTR.

4. **`alioth-sim-provision` & `alioth-switch-sim`**:
   - Mengatur active SIM slot pada hardware switch dual-SIM Poco F3.
   - Mengkonfigurasi ModemManager agar fokus pada port kontrol yang tepat.

5. **Udev Rules**:
   - `77-mm-ignore-sdx55-extra.rules`: Mencegah ModemManager membombardir interface debugging/DIAG yang tidak didukung.
   - `77-mm-sdx55-qrtr.rules`: Menghubungkan node QRTR modem ke ModemManager.
