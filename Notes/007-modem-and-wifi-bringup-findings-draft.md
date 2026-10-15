# Draf Temuan Investigasi: Bring-Up Modem 5G (SDX55) & Wi-Fi (QCA6390) di Fedora Poco F3 (alioth)

Dokumentasi teknis menyeluruh mengenai temuan, analisis kegagalan, pemecahan masalah, dan status operasional modem seluler 5G/LTE Qualcomm SDX55 serta Wi-Fi QCA6390 pada Fedora Linux (KDE Mobile) di Xiaomi Poco F3 (`alioth`).

---

## 1. Arsitektur Perangkat Keras

Poco F3 (`alioth`) ditenagai SoC Qualcomm Snapdragon 870 (SM8250-AC). Karakteristik kunci:
1. **Tidak Memiliki Modem Internal**: Berbeda dengan SoC mid-range, SM8250 adalah prosesor aplikasi (AP) murni tanpa baseband modem terintegrasi.
2. **Modem Eksternal SDX55 (PCIe2)**:
   - Terhubung melalui bus PCIe controller ke-2 (`pcie@1c10000`, domain `0002:00:00.0`, endpoint `0002:01:00.0`, PCI ID `17cb:0306`).
   - Arsitektur **Flashless**: Chip modem tidak memiliki storage NAND/eMMC onboard. Seluruh 16 biner firmware serta partisi kalibrasi NV/IMEI berada di storage internal UFS ponsel (`/dev/sda` dan `/dev/sde`).
   - Komunikasi host-endpoint menggunakan bus **Qualcomm MHI** (Modem Host Interface).
3. **Chip Wi-Fi/Bluetooth QCA6390 (PCIe0)**:
   - Terhubung melalui bus PCIe controller ke-0 (`pcie@1c00000`, domain `0000:00:00.0`, endpoint `0000:01:00.0`, PCI ID `17cb:1101`).
   - Menggunakan driver in-kernel `ath11k_pci` dan memerlukan power sequencing dari PMU (`pwrseq-qcom-wcn`).

---

## 2. Temuan Investigasi & Solusi Modem SDX55

### 2.1 Siklus Boot Awal & Masalah Retensi TCSR (SBL vs Linux)
- **Gejala Awal**: Modem terdeteksi di PCIe saat awal boot, namun port `/dev/wwan0sahara0` pasif dan tidak pernah mengirimkan paket `SAHARA_HELLO_REQ`.
- **Akar Masalah**:
  1. Bootloader ponsel (**XBL**) di detik 0.0 sudah menyalakan PCIe2, mengunggah `sbl1.mbn` via protokol BHI, dan menjalankan SBL modem sebelum kernel Linux melakukan probe.
  2. Karena flashless, SBL mendeteksi ketiadaan flash lokal, menyetel bit DLOAD di register volatil TCSR `0x01fd3000`, lalu masuk ke spin-loop pasif menunggu reset terkoordinasi dari host.
  3. Pemicuan reset menggunakan MMIO MHI `0xb0` (`MHI_SOC_RESET_REQ`) mereset seluruh core baseband dan **menghapus bit retensi TCSR**, membuat modem kehilangan status bootloader-nya.
- **Solusi**:
  - Reset dilakukan via **SPMI Power-On register sequence** pada slave 8 (`pmx55` / `pmic@8`):
    - Tulis `0` ke register `0x863` (`SW_RST_S2_CTL2`), tunda 500 µs.
    - Tulis `1` ke register `0x862` (`SW_RST_S2_CTL`, tipe warm reset).
    - Tulis `0x80` ke `0x863` (`RESET_EN`), tunda 500 µs.
    - Tulis `0xA5` ke `0x864` (`SW_RST_GO`).
  - Warm reset via SPMI menjaga tegangan `VDD_MODEM` tetap stabil sehingga register retensi TCSR `0x01fd3000` tidak terhapus.

### 2.2 Jalur Kendali Handshake TLMM ESOC (`modem-ctrl`)
- **Gejala**: SBL menolak melanjutkan inisialisasi boot table jika Application Processor (AP) dianggap belum siap.
- **Solusi**:
  - Diterapkan driver platform `modem-ctrl` yang mengendalikan jalur GPIO TLMM:
    - `ap2mdm_status` (GPIO 56)
    - `ap2mdm_errfatal` (GPIO 57)
    - `mdm2ap_status` (GPIO 3)
    - `mdm2ap_errfatal` (GPIO 1)
  - Setelah SPMI warm reset, host menunggu **150 ms**, lalu menaikkan `ap2mdm_status = 1`. Sinyal ini memberi tahu SBL bahwa host Linux siap melayani transfer Sahara.

### 2.3 Retraining PCIe Link & Restorasi BAR0/BAR2
- **Gejala**: Setelah modem melakukan soft-reset, link PCIe2 turun ke status putus (`ff ff ff ff`). Saat dilatih ulang, konfigurasi BAR0 (`0x10`) dan BAR2 (`0x18`) kembali ke nilai default `0x00000004`, memicu error pembacaan BHI `0xffffffff` (`-ERANGE`).
- **Solusi**:
  - Fungsi in-kernel `qcom_pcie_cycle_endpoint_reset()` me-retrain link host bridge PCIe2 hingga Gen3 x2 (8.0 GT/s) kembali aktif.
  - Driver `mhi-pci-generic` secara eksplisit memulihkan register:
    - BAR0: `0x64300004` (64-bit non-prefetchable)
    - BAR2: `0x64301004` (64-bit non-prefetchable)
    - PCI Command: bit 2 (`PCI_COMMAND_MASTER`) diaktifkan (`0x0006`).

### 2.4 ARM-SMMU Identity Domain (SID `0x1d01`)
- **Gejala**: Akses DMA modem memicu translation fault:
  ```text
  arm-smmu 15000000.iommu: Unhandled context fault: fsr=0x402, iova=0x92800000, SID=0x1d01
  ```
- **Solusi**:
  - Di `drivers/iommu/arm/arm-smmu/arm-smmu.c`, perangkat `17cb:0306` dipetakan ke `IOMMU_DOMAIN_IDENTITY` (1:1 physical bypass), menghilangkan fault tanpa mengganggu domain translasi DPU, GPU, dan USB.

### 2.5 Bandwidth Scaling Handshake MHI Core
- **Temuan**: SBL modem meminta penyesuaian bandwidth link PCIe via dedicated event ring `MHI_ER_BW_SCALE`. Jika host tidak membalas ke doorbell `0x7e` (doorbell 126), modem berhenti memuat firmware.
- **Solusi**:
  - Diimplementasikan callback `mhi_init_bw_scale()` di `init.c` dan worker `mhi_bw_scale_work()` di `main.c`. Host secara otomatis membalas request sequence dengan `ACK (0)`.

### 2.6 Server Firmware Sahara (`sahara_srv.py`) & Perbaikan Bug Debug Mode
- **Temuan**: Di repositori referensi upstream (`cancelledbit`), skrip `sahara_srv.py` mengirim paket `SWITCH_MODE(2)` (Memory Debug Mode) setelah selesai memuat seluruh image. Akibatnya, modem freeze dan masuk ke sesi dump memori alih-alih booting ke AMSS.
- **Solusi**:
  - Kode `SWITCH_MODE(2)` dihapus dari handler `DONE_RESP`. Setelah image ke-16 (`apps.mbn`) selesai diunggah, server membiarkan modem melanjutkan transisi alami ke Mission Mode.

### 2.7 Remote File System (EFS) & TFTP Server (Instance 3)
- **Temuan**:
  1. Pada saat masuk ke Mission Mode, modem membuka channel MHI 10/11 (`EFS` / `/dev/wwan0xmmrpc0`) dan meminta sinkronisasi NVRAM. Jika tidak dilayani, modem memutuskan link PCIe setelah 16 detik.
  2. Modem mengunduh file carrier configuration via TFTP over QRTR (`tqftpserv`). Namun modem mencari layanan TFTP pada **QRTR instance 3** (bukan instance default 1).
- **Solusi**:
  - `tqftpserv` di-patch pada pemanggilan biner `qrtr_publish(fd, 4096, 3, 0)`.
  - Direktori carrier `/lib/firmware/qcom/sm8250/xiaomi/alioth/modem_pr/` disiapkan agar `tqftpserv` dapat melayani `mbn_hw.dig` dan `mbn_sw.dig`.
  - Server `efs_srv.py` menangani transaksi pembacaan dan penulisan berkala untuk `m9kefs1` dan `m9kefs2`.
  - Partisi riil `mdm1m9kefs1..3` di-dump ke `/lib/firmware/qcom/sdx55m/efs1..3_real.bin` (menggantikan file placeholder dummy 512-byte yang merusak IMEI).

### 2.8 Proteksi PIN Kartu SIM
- **Temuan**: Kartu SIM berada dalam status `pin1-or-upin-pin-required`, menyebabkan registrasi jaringan tertahan (`CS/PS detached`).
- **Solusi**:
  - PIN1 diverifikasi dan proteksi dinonaktifkan permanen via QMI:
    ```sh
    qmicli -d qrtr://3 --uim-verify-pin="PIN1,0852,session-type=card-slot-1"
    qmicli -d qrtr://3 --uim-set-pin-protection="PIN1,disable,0852,session-type=card-slot-1"
    ```
  - Status kartu SIM kini otomatis `ready` pada setiap boot.

---

## 3. Integrasi ModemManager & NetworkManager (KDE GUI)

### 3.1 Penyebab Modem Sempat Muncul di GUI Lalu Hilang
Saat ModemManager berhasil mendeteksi modem via QRTR, modem sempat muncul penuh:
```text
path: /org/freedesktop/ModemManager1/Modem/0
manufacturer: QUALCOMM INCORPORATED
equipment id: 864856058858184 (IMEI valid)
operator: IND INDOSAT (51001)
signal quality: 88%
state: registered (attached)
```
Namun, beberapa detik kemudian modem hilang dari GUI karena:
1. **Kegagalan Driver Bearer**: NetworkManager mencoba menginisialisasi sesi data melalui ModemManager. Plugin `qcom-soc` bawaan ModemManager upstream Fedora hanya mendukung driver net `bam-dmux` dan `ipa`. Ketika mendeteksi interface `mhi_hwip0` (driver `mhi_net`), plugin melempar error:
   ```text
   Unsupported QMI kernel driver for 'net/mhi_hwip0': mhi_net
   ```
2. **Timeout & Invalidation**: Setelah 10 kali timeout transaksi berturut-turut pada port `qrtr3`, ModemManager menandai modem sebagai `unusable/invalid` dan menghapus objeknya dari D-Bus.
3. **SIM Swap Reprobe Loop**: Adanya event status kartu SIM saat inisialisasi awal ditafsirkan oleh ModemManager upstream sebagai SIM swap fisik, memicu siklus reprobe berulang tanpa henti.

### 3.2 Solusi Data Direct Saat Ini (Berjalan Lancar)
Untuk memotong ketergantungan pada ModemManager yang belum di-patch:
- Sesi data packet diangkat langsung oleh `data_up.py`:
  - Interface virtual `rmnet0` dibuat di atas `mhi_hwip0` dengan protokol QMAP multiplexing (`mux_id 1`, MTU 1500).
  - Alokasi IP seluler publik carrier (Indosat) diterima secara dinamis (`10.x.x.x`).
  - DNS uplink (`1.1.1.1` & `114.5.5.5`) serta default route didaftarkan ke `systemd-resolved` via `resolvectl`.
- **Hasil**: Akses internet seluler berjalan normal (ping 39 ms, browsing web, dan streaming YouTube berfungsi).

---

## 4. Temuan Investigasi Wi-Fi (QCA6390)

### 4.1 Penyebab Wi-Fi Tidak Muncul / Mati
- **Gejala**: Antarmuka `wlp1s0` tidak terbentuk di `ip link`, chip `17cb:1101` tidak muncul di `lspci`, atau chip terdeteksi di PCIe namun mac80211 / `wlp1s0` tidak pernah selesai diinisialisasi (`qca6390 hw2.0` terdeteksi namun interface tidak up).
- **Akar Masalah**:
  1. **Mismatch Versi Kernel & Modul**: Ponsel melakukan boot menggunakan kernel baru **7.2.0**, sedangkan folder sistem `/lib/modules/` hanya berisi modul versi lama **6.19.6-pipa**. Modul `7.2.0` belum ada di rootfs.
  2. **Kegagalan Power Sequencer**: Pada kernel 7.2.0, chip Wi-Fi QCA6390 dikendalikan oleh modul power sequencing `pwrseq-qcom-wcn.ko`. Tanpa modul ini di `/lib/modules/7.2.0/`, chip tidak mendapat power rail dari PMIC, link PCIe0 tidak up, dan driver `ath11k_pci` tidak dapat mengenali hardware.
  3. **Konflik State Transition MHI Core (SDX55 vs QCA6390)**:
     - Patch in-kernel `0002-add-modem-sdx55m-support.patch` menambahkan transisi manual paksa `DEV_ST_TRANSITION_MISSION_MODE` dan timeout bypass SBL pada event interrupt/ready state.
     - Patch tersebut semula bersifat global dan tidak memfilter pengontrol MHI. Akibatnya, chip Wi-Fi QCA6390 (yang juga memakai bus MHI via `mhi1`) dipaksa masuk ke Mission Mode sebelum firmware selesai mengunduh BDF/kalibrasi melalui QRTR MHI channel 20/21, memicu drop paket control socket QRTR dan membuat inisialisasi mac80211 mandek.
- **Solusi**:
  - Seluruh modul kernel `/lib/modules/7.2.0/` diekstrak dari paket APK dan disinkronkan ke rootfs.
  - Perintah `depmod -a 7.2.0` dijalankan untuk memperbarui dependensi modul.
  - Patch `0002-add-modem-sdx55m-support.patch` diperbaiki agar logika bypass SBL & transisi paksa hanya berjalan pada perangkat yang memiliki flag `wait_for_sbl` (khusus modem flashless SDX55), dan mengabaikan transisi ganda jika pengontrol sudah berada di Mission Mode.
  - Hasil: Antarmuka `wlp1s0` otomatis terbentuk saat boot, scan jaringan (`nmcli dev wifi list`) mendeteksi seluruh SSID 2.4 GHz dan 5 GHz, sementara modem SDX55 (`rmnet0`) tetap berjalan normal bersamaan.

---

## 5. Ringkasan Otomasi Rootfs (`prepare-fedora-rootfs.sh`)

Skrip preparasi rootfs Fedora telah diperbarui agar mengotomatisasi seluruh langkah di atas secara mandiri saat membuat `fedora.simg`:

1. **Ekstraksi Modul Dinamis**: Otomatis mencari dan mengekstrak modul kernel dari paket APK pmbootstrap terbaru yang tersedia di host, serta menjalankan `depmod -a` secara offline di rootfs.
2. **Bundel Daemon Modem**: Menginjeksi `sahara_srv.py`, `efs_srv.py`, `data_up.py`, `diagprobe.py`, `modem-up.sh`, dan `alioth-sim-provision` ke `/usr/local/bin/`.
3. **Biner TFTP Native**: Menginjeksi biner `tqftpserv` AArch64 Fedora yang sudah dipatch instance 3 ke `/usr/local/bin/`.
4. **Otomasi Firmware On-Device (`alioth-modem-firmware.service`)**: Mengekstrak firmware modem dari partisi `modem_a` dan dump partisi `mdm1m9kefs1..3` pada boot pertama.
5. **Early Module Loading (`/etc/modules-load.d/modem.conf`)**: Memuat modul `qrtr`, `qrtr_mhi`, `mhi`, `mhi_wwan_ctrl`, `mhi_net`, dan `rmnet` sejak awal boot.
6. **Akses SSH Default**:
   - `sshd.service` aktif otomatis saat boot.
   - Konfigurasi `PermitRootLogin yes` dan `PasswordAuthentication yes` terpasang di `/etc/ssh/sshd_config.d/01-permitrootlogin.conf`.
   - Host keys digenerate otomatis dan public key user host diinjeksikan.
   - `firewalld` dimatikan agar koneksi SSH via tethering USB (`172.16.42.1`) tidak terblokir.

---

## 6. Rencana Peningkatan Selanjutnya (Roadmap)

1. **Patch Paket ModemManager Fedora**:
   - Mengompilasi ulang package RPM `ModemManager` dengan menerapkan patch `0001-alioth-sdx55-support.patch` dari `cancelledbit`:
     - Menambahkan dukungan driver `mhi_net` dan `rmnet` pada plugin `qcom-soc`.
     - Mengabaikan event SIM swap palsu saat cache IMSI masih kosong.
     - Menghindari pemilihan slot kosong pada modem dual-SIM.
   - Dengan patch ini, kontrol seluler, toggle data, dan indikator sinyal akan muncul permanen di UI status bar KDE Plasma Mobile.
2. **In-Call Voice Audio (VoLTE / CS Call)**:
   - Voice audio dialirkan melalui MHI channel 80/81 (`AUDIO_VOICE_0`) menuju ADSP. Implementasi audio panggilan memerlukan porting stack `q6voice` (MVM/CVS) yang saat ini belum ada di upstream mainline.
