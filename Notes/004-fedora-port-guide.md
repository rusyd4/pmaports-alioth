# Booting Fedora on Xiaomi Poco F3 (alioth)

Self-contained guide to install and boot Fedora ARM64 (KDE Mobile / Plasma) on the Xiaomi Poco F3 (`alioth`).

---

## 1. Prerequisites (Host)

On your Arch Linux host:

```sh
sudo pacman -S android-tools btrfs-progs
```

---

## 2. Kernel Compilation (pmbootstrap)

Mainline drivers for the display panel, SPI bus, and touchscreen must be compiled as built-ins (`=y`):

1. **Kernel configuration** (`linux-postmarketos-qcom-sm8250-alioth/config-postmarketos-qcom-sm8250-alioth.aarch64`):
   ```kconfig
   CONFIG_SPI_QCOM_GENI=y
   CONFIG_TOUCHSCREEN_FT8756=y
   CONFIG_DRM_PANEL_SAMSUNG_AMS667XX01=y
   ```

2. **Build kernel packages**:
   ```sh
   pmbootstrap build firmware-xiaomi-alioth
   pmbootstrap build linux-postmarketos-qcom-sm8250-alioth
   pmbootstrap build device-xiaomi-alioth
   ```

---

## 3. Prepare Fedora Rootfs (Pre-Boot Automation)

1. **Extract and mount the raw Fedora image**:
   ```sh
   unxz Fedora-KDE-Mobile-Disk-*.raw.xz
   sudo losetup -Pf Fedora-KDE-Mobile-Disk-*.raw
   sudo mkdir -p /mnt/fedora
   sudo mount -o subvol=root /dev/loop0p3 /mnt/fedora
   ```

2. **Run pre-boot configuration script**:
   *(Injects kernel modules, firmware, calibrated ALSA state, audio UCM profiles, Bluetooth services, Wi-Fi powersave, SSH keys, and fixes fstab in one step)*:
   ```sh
   sudo ./prepare-fedora-rootfs.sh /mnt/fedora
   ```

3. **Convert to Android Sparse image**:
   ```sh
   sudo sync
   sudo umount /mnt/fedora
   sudo img2simg /dev/loop0p3 ~/fedora-rootfs.simg
   sudo losetup -d /dev/loop0
   ```
   ```sh
   sudo sync
   sudo umount /mnt/fedora
   sudo img2simg /dev/loop0p3 ~/fedora-rootfs.simg
   sudo losetup -d /dev/loop0
   ```

---

## 4. Generate the Boot Image (`boot_fedora.img`)

Because `pmbootstrap` sets cmdline arguments aimed at Alpine's UUID, repack the initramfs kernel using `mkbootimg` to mount Fedora's Btrfs subvolume directly:

```sh
mkdir -p /tmp/boot_unpack
unpack_bootimg \
  --boot_img ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/boot/boot.img \
  --out /tmp/boot_unpack

# For standalone Fedora on userdata:
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

---

## 5. Flash via Fastboot

Reboot phone to Fastboot mode (Power + Volume Down):

```sh
# 1. Erase OEM DTBO (avoids device tree conflicts)
fastboot erase dtbo_b

# 2. Flash repacked boot image to slot B
fastboot flash boot_b ~/boot_fedora.img

# 3. Flash Fedora rootfs to userdata
fastboot flash userdata ~/fedora-rootfs.simg

# 4. Activate slot B and reboot
fastboot set_active b
fastboot reboot
```

---

## 6. Post-Installation Tips

### Audio Volume Boost
The Cirrus Logic `cs35l41` hardware amplifier defaults to low analog/digital gain stages in ALSA:
* In terminal on the phone, run `alsamixer` -> press **F6** -> select the Qualcomm sound card.
* Raise `RCV Analog PCM Volume`, `LCV Analog PCM Volume`, `RCV Digital PCM Volume`, and `LCV Digital PCM Volume` to maximum.
* Save the mixer state: `sudo alsactl store`.
* Alternatively, enable **"Raise maximum volume / Allow volume over 100%"** in KDE Sound Settings.

## 7. 5G/LTE Cellular Modem (Qualcomm SDX55) Bring-Up

The Snapdragon 870 SoC has no integrated modem; the Xiaomi Poco F3 (`alioth`) connects to a standalone Qualcomm SDX55 chip over PCIe (`pcie2`). The modem is flashless (it contains no onboard storage and pulls all firmware and NV from the host UFS partitions).

### A. Kernel Requirements
The kernel must be built with `0002-add-modem-sdx55m-support.patch` and the following configuration options enabled:
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

### B. Userspace Firmware & Tooling
1. **Firmware Extraction** (from phone's internal partitions):
   - Firmware binaries: copy from Android `/vendor/firmware_mnt/image/sdx55m/*` to `/lib/firmware/qcom/sdx55m/`.
   - Carrier configuration files: copy `/image/modem_pr` to `/lib/firmware/qcom/sm8250/xiaomi/alioth/modem_pr`.
   - Real NV/IMEI partitions (do not use stock placeholder `efs*.bin`):
     ```sh
     dd if=/dev/disk/by-partlabel/mdm1m9kefs1 of=/lib/firmware/qcom/sdx55m/efs1_real.bin bs=1M
     dd if=/dev/disk/by-partlabel/mdm1m9kefs2 of=/lib/firmware/qcom/sdx55m/efs2_real.bin bs=1M
     dd if=/dev/disk/by-partlabel/mdm1m9kefs3 of=/lib/firmware/qcom/sdx55m/efs3_real.bin bs=1M
     ```

2. **Required Services**:
   - `tqftpserv`: Qualcomm TFTP server published on QRTR instance 3 (`tqftpserv -d`).
   - `sahara_srv.py`: Python Sahara image server serving boot binaries on `/dev/wwan0firehose0`.
   - `efs_srv.py`: Remote file system server serving NV partitions on `/dev/wwan0xmmrpc0`.
   - `data_up.py` / `modem-up.sh`: Service script that brings up the radio, binds the WDS QMI client, configures raw-ip QMAP on `rmnet0`, and sets up DNS routing via `resolvectl`.

### C. Disabling SIM PIN Protection
If your SIM card is locked with a PIN:
```sh
# Verify PIN1 (example PIN 0852 on slot 1):
qmicli -d qrtr://3 --uim-verify-pin="PIN1,0852,session-type=card-slot-1"

# Disable PIN protection permanently:
qmicli -d qrtr://3 --uim-set-pin-protection="PIN1,disable,0852,session-type=card-slot-1"
```

---

## 8. Credits & Acknowledgments

- **[cancelledbit/alioth-modem](https://github.com/cancelledbit/alioth-modem)**:
  Groundbreaking research and complete implementation of the SDX55 bring-up on mainline Linux for Poco F3 / Redmi K40 (`alioth`). Provided the reference patches for ESOC PMIC reset (`pmx55`), TLMM handshake lines, MHI bandwidth scaling (`bw_scale`), EFS remote filesystem server architecture, and QRTR/TFTP instance mapping.
- **postmarketOS Community & SoC SM8250 Mainlining Team**:
  Device tree foundation, initial display panel, touchscreen drivers, and audio UCM profiles for the Snapdragon 865/870 platform.
- **Linux MSM / Qualcomm Innovation Center (QuIC)**:
  Upstream MHI bus subsystem, QRTR router, and RmNet MAP drivers.
