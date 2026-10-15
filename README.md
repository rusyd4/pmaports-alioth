**pmaport for xiaomi poco f3 - alioth**

**Table of Contents**
- [1. Installation Guide](#1-installation-guide)
  - [1.1. Single Boot](#11-single-boot)
    - [Option A: postmarketOS](#option-a-postmarketos)
    - [Option B: Fedora ARM64 Standalone](#option-b-fedora-arm64-standalone)
  - [1.2. Dual Boot (AOSP + Fedora)](#12-dual-boot-aosp--fedora)
    - [Step 1: UFS Partitioning](#step-1-ufs-partitioning-using-prebuilt-parted)
    - [Step 2: Flash AOSP (Slot A)](#step-2-install-aosp-slot-a)
    - [Step 3: Flash Fedora (Slot B)](#step-3-install-fedora-slot-b)
    - [Step 4: Switching Operating Systems](#step-4-switching-operating-systems)
- [2. Current State](#2-current-state)
- [3. Introduction](#3-introduction)
- [4. Getting the Kernel to Work](#4-getting-the-kernel-to-work)
  - [4.1. Key Config Changes from nikroks defconfig:](#41-key-config-changes-from-nikroks-defconfig)
- [5. Getting UART Logs](#5-getting-uart-logs)
  - [5.1. Kernel UART Configuration](#51-kernel-uart-configuration)
  - [5.2. Finding UART Pins on the Phone's PCB](#52-finding-uart-pins-on-the-phones-pcb)
  - [5.3. UART to USB-A Converter with Level Shifter from NPN Transistors](#53-uart-to-usb-a-converter-with-level-shifter-from-npn-transistors)
  - [5.4. Arduino Code](#54-arduino-code)
  - [5.5. Capturing the Logs](#55-capturing-the-logs)

---
# 1. Installation Guide

### Prebuilt Utilities Included in Repository
- `tools/parted/`: Self-contained ARM64 `parted` bundle for TWRP/OrangeFox custom recovery via `adb`.
- `tools/qbootctl` / `device-xiaomi-alioth/qbootctl`: Statically compiled aarch64 `qbootctl` (from [linux-msm/qbootctl](https://github.com/linux-msm/qbootctl)) for Qualcomm A/B slot switching without external dependencies. Automatically installed to `/usr/local/bin/qbootctl` on Fedora via `prepare-fedora-rootfs.sh`.

---

## 1.1. Single Boot

### Option A: postmarketOS

Build packages and rootfs via `pmbootstrap`:
```sh
# Flash rootfs and kernel to Slot B
fastboot erase dtbo_b
pmbootstrap flasher flash_rootfs --partition userdata
pmbootstrap flasher flash_kernel --partition boot_b
fastboot set_active b
fastboot reboot
```

### Option B: Fedora ARM64 Standalone

1. **Build prepared Fedora rootfs sparse image:**
   ```sh
   sudo ./build-fedora-rootfs.sh /path/to/Fedora-KDE-Mobile-Disk-*.raw fedora-rootfs.simg
   ```
   *(Or mount manually and run `sudo ./prepare-fedora-rootfs.sh /mnt/fedora`, which injects modules, firmware, UCM2 audio profiles, cellular config, modem services, and prebuilt `qbootctl`).*

2. **Repack `boot.img` for `userdata` partition:**
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

3. **Flash via Fastboot:**
   ```sh
   fastboot erase dtbo_b
   fastboot flash boot_b ~/boot_fedora.img
   fastboot flash userdata ~/fedora-rootfs.simg
   fastboot set_active b
   fastboot reboot
   ```

---

## 1.2. Dual Boot (AOSP + Fedora)

Dual boot Android (Slot A) and Fedora Linux (Slot B) by splitting the 242 GB `userdata` partition into two 121 GB partitions:
- Partition 35: `userdata` (121 GB, Android storage, encrypted)
- Partition 36: `linux` (121 GB, Btrfs, Fedora rootfs)

### Step 1: UFS Partitioning (using prebuilt `parted`)

1. Boot into OrangeFox or TWRP recovery:
   ```sh
   fastboot boot OrangeFox-alioth.img
   ```

2. Push prebuilt ARM64 `parted` from this repository:
   ```sh
   adb push tools/parted /tmp/
   adb shell "chmod +x /tmp/parted/parted /tmp/parted/bin/parted /tmp/parted/lib/ld-musl-aarch64.so.1"
   ```

3. Repartition `/dev/block/sda` in `adb shell`:
   ```sh
   adb shell
   cd /tmp/parted

   # Remove original 242 GB userdata partition
   ./parted /dev/block/sda rm 35
   # Type 'i' when prompted (Ignore/Cancel)

   # Create 121 GB userdata for Android
   ./parted /dev/block/sda mkpart userdata ext4 11.4GB 132GB

   # Create 121 GB dedicated linux partition for Fedora
   ./parted /dev/block/sda mkpart linux btrfs 132GB 253GB

   # Verify partition table
   ./parted /dev/block/sda print
   exit
   ```

4. Reload partition table and format Android data:
   ```sh
   adb reboot recovery
   ```
   In recovery GUI: **Wipe -> Format Data -> type `yes`**.

### Step 2: Install AOSP (Slot A)

1. Activate Slot A:
   ```sh
   fastboot set_active a
   ```
2. Flash your ROM zip (LineageOS, PixelOS, etc.) via recovery or fastboot.
3. Boot Android once to complete initial setup and initialize encryption on partition 35.

### Step 3: Install Fedora (Slot B)

1. **Repack `boot.img` for `linux` partition (`pmos_root=/dev/disk/by-partlabel/linux`):**
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

2. **Flash Fedora to Slot B and dedicated `linux` partition:**
   ```sh
   fastboot erase dtbo_b
   fastboot flash boot_b ~/boot_fedora_dualboot.img
   fastboot flash linux ~/fedora-rootfs.simg
   ```

### Step 4: Switching Operating Systems

- **Via Fastboot (from PC):**
  ```sh
  fastboot set_active a && fastboot reboot   # Boot Android
  fastboot set_active b && fastboot reboot   # Boot Fedora
  ```
- **From inside Android (Root):**
  ```sh
  su
  bootctl set-active-boot-slot 1
  reboot
  ```
  *(Or use the BootControl app from F-Droid).*
- **From inside Fedora:**
  ```sh
  sudo qbootctl -s a
  sudo reboot
  ```
  *(Prebuilt `qbootctl` is installed in `/usr/local/bin/qbootctl` automatically).*

# 2. Current State
Device was built and tested with plasma-mobile UI with systemd.

If **building kernel crashes** because of the RAM usage disable `Link Time
Optimization` in the defconfig. 

It works without major issues, most importantly WiFi with `nmtui` is available.

Little cranky at times, TODO:
 - ~~Improve camera and speakers quality ~~ Add camera patches

Done:
 - ~~Move to generic sm8250-linux instead of nikroks~~
 - ~~Enable bluetooth - disabled to enable UART debugging~~
 - ~~Changed NetworkManagers powersave option - changed powersave to 2 in NetworkManager for better responsivness~~
 - ~~Fix why **the phones needs to be rebooted after flashing** because GUI doesnt want to start~~
 - ~~Verify which defconfig options are needed~~

# 3. Introduction
This phone uses qcom sm8250 CPU and adreno650 GPU, so the port was based on existing postmarketOS work for this chip. Good starting point: [Xiaomi Mi Pad 5 Pro (xiaomi-elish)](https://wiki.postmarketos.org/wiki/Xiaomi_Mi_Pad_5_Pro_(xiaomi-elish))

I also found this [alioth pmaport by nikroks](https://github.com/mainlining/pmaports/tree/nikroks/alioth), but for some reason it crashes straight back to fastboot.

Good guy @Maledict found that defconfig from Mi Pad 5 Pro worked with [linux fork by nikroks](https://github.com/mainlining/linux/tree/nikroks/alioth).

We can call this our starting point.

# 4. Getting the Kernel to Work

The nikroks kernel had potential but needed some config tweaking. Started with the basic setup:
```bash
source envkernel.sh
make defconfig sm8250.config
```
 All changes were made with `make menuconfig`.

The first thing I checked was the CPU architecture of the Poco F3: it uses **Cortex A77** and **Cortex A55** cores. According to the [ARM manual](https://developer.arm.com/documentation/101111/0101/AArch64-System-registers/ID-AA64MMFR2-EL1--AArch64-Memory-Model-Feature-Register-2--EL1?lang=en) these cores support 48 bit virtual addresses and do not implement LVA (Large Virtual Addressing). The relevant ID register field:

```
 VARange, [19:16]

    Indicates support for a larger virtual address. The value is:

    0x0
        VMSAv8-64 supports 48-bit virtual addresses. 
```

Based on this, I changed the kernel configuration to match the hardware capabilities:
- `CONFIG_ARM64_VA_BITS` to 48
- `CONFIG_PGTABLE_LEVELS` to 4


MMC doesn't seem needed since we only have UFS memory, so disabled `CONFIG_MMC`. Same deal with `CONFIG_ATA`.

Phone has GPU so DRM should work - adreno650 support is there.

## 4.1. Key Config Changes from nikroks defconfig:
```
changed preempt to none

CONFIG_DM_INTEGRITY to y
CONFIG_USB_MASS_STORAGE to n
CONFIG_ANDROID_BINDERFS to n
CONFIG_ZRAM_BACKEND_ZSTD to y

!!!! CONFIG_EFI_ZBOOT to n !!!! <-- THE IMPOSTOR
```

*The breakthrough:* After changing `CONFIG_EFI_ZBOOT` to `n`, it started working! Since the phone is missing EFI, this part was never being decompressed - and that was the biggest issue with the config. UART logs showing missing DTB pointed at the decompression issue and further confirms that the phone doesn't have EFI.

# 5. Getting UART Logs

UART logs were configured before the elish defconfig was discovered as working. Because the nikroks defconfig failed pretty early, the only logs visible in early work were **Android BootLoader (ABL) logs**, which is still cool. 

 - Dumps can be found [here](Notes/uart_logs).

## 5.1. Kernel UART Configuration
**Device Tree:** The kernel DTB must be patched to designate the appropriate UART interface as serial0 output, as demonstrated in [this patch](linux-postmarketos-qcom-sm8250-alioth/0001-modified-dts-to-see-kernel-data-on-uart.patch).

**Kernel Command Line:** The following parameters enable comprehensive UART logging: \
`deviceinfo_kernel_cmdline="console=ttyMSM0,115200n8 earlycon earlyprintk loglevel=15 console=tty0"`

Where:
 - `console=ttyMSM0,115200n8` - Primary UART console at 115200 baud. MSM is qcom specific
 - `earlycon` - Enable early console during boot initialization
 - `earlyprintk` - Enable early kernel printk messages
 - `loglevel=15` - Maximum kernel log verbosity (debug level)
 - `console=tty0` - Mirror output to virtual terminal (phone's screen)

## 5.2. Finding UART Pins on the Phone's PCB

[pmOS wiki for xiaomi poco F3](https://wiki.postmarketos.org/wiki/Xiaomi_POCO_F3_(xiaomi-alioth)) already contains info about UART TX location.

To verify it I looked for the phone schematic on yandex and [found it here](https://vk.com/wall-203976641_3526) (but it can contain viruses, use at your own risk).

| ![UART schema](images/uart_pins_schema.png) | ![UART TX PCB](images/uart_tx_pcb.png) |
| ------------------------------------------- | -------------------------------------- |
| _UART pins described on phone's schema_      | _UART TX location on the PCB_          |

We don't really need RX for reading logs. Also according to the PCB schema, RX pin (TP7307) is located on the other side of the PCB which would require disassembling the whole board.

So I decided to solder a wire to the UART TX pin only, and for ground I connected GND to the phone’s metal chassis, which is tied to the board's ground. Example image from pmOS wiki:
| ![UART TX on alioth PCB](images/Alioth_uart.jpg) |
| ------------------------------------------------ |
| _UART TX marked on the poco F3 PCB_              |

## 5.3. UART to USB-A Converter with Level Shifter from NPN Transistors

I didn't have a UART to USB-A converter so I had to get creative. Found an _Arduino UNO R3_ which by default communicates with the computer via UART protocol on pins 0 and 1.

**Be careful:** if anything is plugged into pins 0 or 1, flashing can fail. Keep this in mind when uploading code.

**The voltage problem:** After checking with multimeter, the phone's UART works on **1.8V** while Arduino's logic works on **5V** (possibly could work with 3.3V). So I had to design a level shifter from what was available.

In my Arduino kit I found a few [NPN transistors BC547B](https://www.farnell.com/datasheets/410427.pdf) - their specs were fast enough for 115200 bit/s, so I used them to create this level shifter:

| ![level shifter schema](images/level_shifter-schema.png)       |
| -------------------------------------------------------------- |
| _Level shifter with transistors as if connected to the device_ |

**Don't forget to connect phone's ground to Arduino's ground, for the same reference point.**

Final working connection:
| ![level shifter photo](images/uart_connection_photo.jpeg) |
| --------------------------------------------------------- |
| _Phone connected to the arduino via level shifter_        |

## 5.4. Arduino Code

Simple passthrough from RX to TX:
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
      Serial.println(receivedMessage);  // Print the received message in the Serial monitor
      receivedMessage = "";  // Reset the received message
    } 
    else {
      receivedMessage += receivedChar;  // Append characters to the received message
    }
  }
}
```

## 5.5. Capturing the Logs

Connect arduino to the computer and listen via `minicom`, logs will be saved to uart_logs.txt file:
```bash
minicom -b 115200 -D /dev/ttyACM0 -C uart_logs.txt
```

