# Hardware UART Debugging Guide for Poco F3 (alioth)

Panduan menangkap log bootloader Android (ABL) dan early console kernel via UART hardware pin pada board Poco F3.

---

## 1. Lokasi Pin UART pada PCB

| Titik Uji PCB | Jalur UART | Tegangan Logika | Lokasi Fisik |
| :--- | :--- | :--- | :--- |
| **TX** (Test Point) | Serial Output (Phone → PC) | **1.8V** | Sisi depan PCB utama |
| **TP7307 (RX)** | Serial Input (PC → Phone) | **1.8V** | Sisi belakang PCB utama (memerlukan lepas board) |
| **GND** | Ground Referensi | 0V | Chassis logam pelindung board |

*Catatan*: Untuk keperluan membaca log bootloader & kernel, kita hanya membutuhkan pin **TX** dan **GND**.

![UART Schema](../../images/uart_pins_schema.png)
![UART TX on PCB](../../images/Alioth_uart.jpg)

---

## 2. Rangkaian Level Shifter Transistor (1.8V → 5V / 3.3V)

Pin UART pada smartphone beroperasi pada level logika **1.8V**. Menghubungkan langsung pin 1.8V ke logic level 5V Arduino dapat merusak SoC Snapdragon.

Rangkaian level shifter menggunakan transistor NPN umum (BC547B / 2N2222):

![Level Shifter Schema](../../images/level_shifter-schema.png)

Pastikan Ground smartphone terhubung ke Ground rangkaian shifter/Arduino sebagai titik referensi potensial bersama.

![Level Shifter Photo](../../images/uart_connection_photo.jpeg)

---

## 3. Firmware Arduino UNO Passthrough (Baud: 115200)

```cpp
String receivedMessage;

void setup() {
  Serial.begin(115200);
  Serial.print("UART adapter begin:\r\n");
}

void loop() {
  while (Serial.available() > 0) {
    char receivedChar = Serial.read();

    if (receivedChar == '\n') {
      Serial.println(receivedMessage);
      receivedMessage = "";
    } else {
      receivedMessage += receivedChar;
    }
  }
}
```

*Perhatian*: Lepas kabel pada Pin 0 & 1 Arduino saat mengunggah sketch agar flashing bootloader Arduino tidak bentrok.

---

## 4. Konfigurasi Kernel untuk Output UART

1. **Device Tree Patch**:
   DTB kernel harus memetakan UART console ke serial0 (`ttyMSM0`):
   Lihat patch `linux-postmarketos-qcom-sm8250-alioth/0001-modified-dts-to-see-kernel-data-on-uart.patch`.

2. **Kernel Cmdline**:
   ```sh
   console=ttyMSM0,115200n8 earlycon earlyprintk loglevel=15 console=tty0
   ```
   - `ttyMSM0,115200n8`: Port console fisik Qualcomm MSM pada baud rate 115200.
   - `earlycon` & `earlyprintk`: Menampilkan output printk sebelum tty subsystem lengkap terinisialisasi.
   - `console=tty0`: Melakukan mirror log ke framebuffer layar smartphone.

---

## 5. Menangkap Log via Minicom

Hubungkan Arduino ke PC Host via USB:
```bash
minicom -b 115200 -D /dev/ttyACM0 -C uart_logs.txt
```

Arsip log bootloader dan dmesg awal tersimpan di direktori `Notes/uart_logs/`.
