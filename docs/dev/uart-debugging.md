# Hardware UART Debugging Guide for Poco F3 (alioth)

Guide to capturing Android BootLoader (ABL) and early kernel printk logs using hardware UART test points on the Poco F3 PCB.

---

## 1. PCB UART Pin Locations

| Test Point | UART Line | Logic Voltage | Location |
| :--- | :--- | :--- | :--- |
| **TX** | Serial Transmit (Phone → PC) | **1.8V** | Front side of main PCB |
| **TP7307 (RX)** | Serial Receive (PC → Phone) | **1.8V** | Back side of main PCB (requires full board teardown) |
| **GND** | Ground Reference | 0V | Metal chassis shield |

*Note*: For capturing boot logs, only **TX** and **GND** are necessary.

![UART Schema](../../images/uart_pins_schema.png)
![UART TX on PCB](../../images/Alioth_uart.jpg)

---

## 2. NPN Transistor Level Shifter (1.8V → 5V / 3.3V)

The phone's UART operates at **1.8V logic level**. Connecting it directly to a 5V Arduino will damage the Snapdragon SoC.

Level shifter schematic using generic NPN transistors (BC547B / 2N2222):

![Level Shifter Schema](../../images/level_shifter-schema.png)

Ensure the phone ground is connected to the Arduino/shifter ground to establish a common reference point.

![Level Shifter Photo](../../images/uart_connection_photo.jpeg)

---

## 3. Arduino UNO Passthrough Firmware (Baud: 115200)

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

*Caution*: Disconnect pins 0 and 1 while uploading code to the Arduino to avoid bootloader serial conflicts.

---

## 4. Kernel UART Configuration

1. **Device Tree Patch**:
   The kernel DTB must map `serial0` to `ttyMSM0`:
   See `linux-postmarketos-qcom-sm8250-alioth/0001-modified-dts-to-see-kernel-data-on-uart.patch`.

2. **Kernel Cmdline**:
   ```sh
   console=ttyMSM0,115200n8 earlycon earlyprintk loglevel=15 console=tty0
   ```
   - `ttyMSM0,115200n8`: Primary physical serial port at 115200 baud.
   - `earlycon` & `earlyprintk`: Displays boot output before standard tty subsystems initialize.
   - `console=tty0`: Mirrors console output to the phone screen.

---

## 5. Capturing Logs via Minicom

Connect Arduino to your host PC via USB:
```bash
minicom -b 115200 -D /dev/ttyACM0 -C uart_logs.txt
```

Raw captured bootloader and kernel dmesg logs are archived in `Notes/uart_logs/`.
