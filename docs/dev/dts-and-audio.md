# Device Tree & Audio Architecture Guide

Documentation for Device Tree Source (DTS) handling, DTB decompilation, and CS35L41 audio subsystem debugging on the Xiaomi Poco F3 (`alioth`).

---

## 1. Extracting Device Tree Source (DTS)

To inspect hardware nodes and verify pin multiplexing against the OEM Android kernel:

### 1. Extracting from LineageOS / Android Vendor Boot
The Poco F3 uses a `vendor_boot` partition (Android Boot Header Version 3):
```sh
# Unpack vendor_boot.img
unpack_bootimg --boot_img vendor_boot.img --out /tmp/vb_out

# Decompile DTB binary into readable DTS
dtc -I dtb -O dts -o alioth_vendor.dts /tmp/vb_out/dtb
```

### 2. Extracting from a Running postmarketOS Device
```sh
dtc -I dtb -O dts -o alioth-mainline.dts /boot/sm8250-xiaomi-alioth.dtb
```

DTS dump archives are available in `Notes/dts/`.

---

## 2. Audio Subsystem: Dual Cirrus Logic CS35L41

Alioth uses two Cirrus Logic CS35L41 hardware smart amplifiers controlled via I2C:
- **Earpiece / Receiver (RCV)**: I2C slave address `0x40` on bus `&i2c3`.
- **Loudspeaker (LCV)**: I2C slave address `0x41` on bus `&i2c3`.

### Investigating the "Mystery Buzz" on Suspend / Resume
Early porting iterations suffered from a brief audible buzz immediately upon waking from system suspend:
- Cause: Power rail sequencing order and CS35L41 amplifier GPIO reset handling during D3cold → D0 transitions.
- Full debugging process and DTS adjustments are documented in `Notes/001-debuggin_buzz.md`.

---

## 3. ALSA Use Case Manager (UCM2) Profiles

UCM2 profiles are located in `device-xiaomi-alioth/alsa-ucm-conf/`:
- `alioth.conf`: Card identification and profile entry points.
- `HiFi.conf`: Mixer controls, PCM routing, and amplifier stream management.
- `asound.state`: Default ALSA channel volume calibration.
