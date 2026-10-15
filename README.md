# Mainline Linux on Xiaomi Poco F3 (alioth)

Mainline Linux kernel, postmarketOS packages, and Fedora ARM64 (KDE Plasma Mobile) integration for the **Xiaomi Poco F3 / Redmi K40** (codename: `alioth`), powered by Qualcomm Snapdragon 870 / 865 (SM8250).

---

## What Works / What Doesn't Work

### ✅ What Works
* **Display**: 6.67" AMOLED Samsung AMS667XX01 (1080x2400 @ 120Hz refresh rate)
* **Touchscreen**: FocalTech FT8756 with multi-touch support
* **GPU Acceleration**: Adreno 650 3D hardware acceleration via Mesa Freedreno and Turnip Vulkan
* **Audio**: Stereo sound via dual Cirrus Logic CS35L41 amplifiers with calibrated ALSA UCM2 profiles
* **Wi-Fi 6**: Qualcomm QCA6390 (ath11k via PCIe)
* **Bluetooth**: Bluetooth 5.1 via `hci_qca` UART
* **Cellular Data (5G / 4G)**: Qualcomm Snapdragon X55 (SDX55 flashless modem via PCIe MHI, QRTR, and RmNet)
* **Dual SIM**: Carrier registration and slot selection via Plasma Mobile UI and `alioth-switch-sim`
* **Sensors**: Accelerometer, gyroscope, light, and proximity sensors via `libssc`
* **Battery & Power**: Accurate battery percentage, charging status, and thermal sensors
* **USB**: USB Type-C OTG and USB gadget networking

### 🟡 Work in Progress / What Doesn't Work
* **Camera**: Sensors and ISP (CamX / CAMSS) work in progress
* **VoLTE / In-Call Voice Audio**: Audio routing for cellular voice calls in development
* **Modem Wake from Sleep**: Cellular modem does not recover after system suspend `s2idle` (see [Bugs](#known-bugs--limitations))

---

## Known Bugs & Limitations

* **Cellular Disconnect after Sleep (`s2idle`)**:
  When the device wakes up from system suspend, the SDX55 modem PCIe link desynchronizes (`mhi0: Did not enter M0 state`), dropping cellular data until reboot. Suspend is kept enabled by default to preserve battery life.
  👉 See **[Notes/008-modem-suspend-sleep-bug.md](Notes/008-modem-suspend-sleep-bug.md)** for detailed technical analysis and optional workarounds.

* **No EFI / ZBOOT Support**:
  Alioth bootloader cannot decompress ZBOOT kernels; `CONFIG_EFI_ZBOOT` must remain disabled (`=n`).

* **Audio Amp Buzz without UCM2 Profile**:
  Uncalibrated CS35L41 amplifiers produce a hardware buzzing noise if UCM2 profiles or ALSA volume controls are uninitialized. See **[Notes/001-debuggin_buzz.md](Notes/001-debuggin_buzz.md)**.

---

## Releases & Prebuilt Images

Prebuilt images and download links:
* [**`boot_fedora.img`**](https://drive.google.com/file/d/1o0CHJ_t2dDaJBsw4z18Q8LJnaVj3Tcyg/view?usp=sharing): Boot image for single boot Fedora on the `userdata` partition.
* [**`boot_linux.img`**](https://drive.google.com/file/d/1fjLjzjRp42_BfnwK15h1JfelPD1H3jbA/view?usp=sharing): Boot image for dual boot Fedora on the dedicated `linux` partition.
* [**`fedora-rootfs.simg`**](https://drive.google.com/file/d/1sO2Ap_LXBtzJUo7GjTCbCY0Mi19DqjCf/view?usp=sharing): Prebuilt Fedora KDE Mobile rootfs sparse image with injected kernel modules, firmware, UCM2 audio profiles, cellular services, and `qbootctl`.
* [**`BootControl` APK**](https://github.com/capntrips/BootControl/releases/download/v1.0.0-alpha03/BootControl-v1.0.0-alpha03.apk): Android application to switch A/B slots directly from Android.

Also available on **[GitHub Releases](https://github.com/rusyd4/pmaports-alioth/releases)**.

---

## Documentation

Comprehensive guides are organized in the [`docs/`](docs/) directory:

### 📖 User Guides
* **[Installation Guide](docs/user/installation.md)**: Flashing postmarketOS and standalone Fedora ARM64.
* **[Dual Boot Guide (Android + Fedora)](docs/user/dualboot.md)**: Repartitioning UFS storage to run Android alongside Fedora Linux.
* **[Daily Configuration & Usage](docs/user/configuration.md)**: Audio calibration, dual-SIM switching, SSH setup, and updating safely.

### 🛠️ Developer Guides
* **[Kernel Architecture & defconfig](docs/dev/kernel.md)**: SM8250 kernel tree, defconfig options, and module building.
* **[SDX55 5G Modem Bring-Up](docs/dev/modem-bringup.md)**: MHI architecture, Sahara firmware loading, and QRTR/EFS daemons.
* **[Wi-Fi & Bluetooth Bring-Up](docs/dev/wifi-bluetooth.md)**: QCA6390 MHI power state transitions and Bluetooth UART.
* **[Device Tree & Audio Subsystem](docs/dev/dts-and-audio.md)**: DTS structure, amplifier calibration, and UCM2 profiles.
* **[Hardware UART Debugging](docs/dev/uart-debugging.md)**: Test points, 1.8V level shifters, and serial boot logs.
* **[Fedora Rootfs Automation](docs/dev/fedora-rootfs.md)**: Architecture of `prepare-fedora-rootfs.sh` and sparse image generator.
* **[Notes Directory](Notes/)**: Raw research logs, register dumps, and bring-up history.

---

## Tools Included

* **[`tools/parted/`](tools/parted/)**: Standalone ARM64 GNU Parted bundle (includes musl loader and libraries) for recovery environments (TWRP / OrangeFox).
* **[`tools/qbootctl`](tools/qbootctl)**: Statically linked ARM64 binary to query and toggle A/B boot slots directly from Linux userspace.

---

## Credits & Acknowledgments

* **Vitalii Skorkin ([@nikroks](https://github.com/N1kroks))**: Initial mainline Alioth port, Samsung AMS667XX01 panel driver, and FT8756 touchscreen driver.
* **Bartek G ([@bartek-g](https://github.com/bartek-g))**: pmaports packaging, generic SM8250 kernel migration, DTS maintenance, and audio fixes.
* **[@cancelledbit](https://github.com/cancelledbit)**: Reverse engineering and complete bring-up of the SDX55 modem on mainline Linux ([`alioth-modem`](https://github.com/cancelledbit/alioth-modem)).
* **postmarketOS Community & SM8250 Mainlining Team**: Upstream Linux kernel support for the Snapdragon 865/870 platform.
* **[linux-msm](https://github.com/linux-msm)**: Authors of `qbootctl` and Qualcomm mainline tooling.
* **Freedreno Community**: Open-source Mesa Adreno GPU drivers and Turnip Vulkan.
