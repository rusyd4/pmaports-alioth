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

### Bluetooth Keyboard Pairing
* `hidp` and `uhid` drivers handle Bluetooth keyboards.
* If a keyboard requests PIN / Passkey confirmation and the GUI dialog does not pop up, run `bluetoothctl`:
  ```sh
  bluetoothctl
  default-agent
  pair <MAC_ADDRESS>
  # Type passkey on the keyboard and press Enter if prompted
  trust <MAC_ADDRESS>
  connect <MAC_ADDRESS>
  ```
