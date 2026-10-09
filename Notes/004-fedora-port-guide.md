# Booting Fedora (KDE Mobile) on Xiaomi Poco F3 (alioth)

This guide documents the complete process of booting Fedora 44 (ARM64) with KDE Plasma Mobile on the Xiaomi Poco F3 (Snapdragon 870 / SM8250).

---

## 1. High-Level Architecture

* **Bootloader:** Qualcomm ABL (fastboot) loading slot `b`.
* **Kernel & Initramfs (`boot_b`):** Mainline 6.19.6 kernel with appended Device Tree (`sm8250-xiaomi-alioth.dtb`) and postmarketOS unified initramfs.
* **Root Filesystem (`userdata`):** Fedora ARM64 root filesystem stored in an Android Sparse image, formatted with Btrfs.
* **Handoff Mechanism:**
  1. `boot.img` initramfs boots, loads UFS and USB drivers.
  2. Initramfs searches for the root partition by UUID or label `pmOS_root`.
  3. Mounts the Btrfs `root` subvolume (`subvol=root`) to `/sysroot`.
  4. Calls `switch_root /sysroot /sbin/init` to hand over control to Fedora's systemd.

---

## 2. Host Prerequisites

Install the required tools on Arch Linux:

```sh
sudo pacman -S android-tools multipath-tools btrfs-progs
```

* `android-tools`: provides `fastboot`, `img2simg`, and `unpack_bootimg`.
* `multipath-tools`: provides `kpartx` required by pmbootstrap.
* `pmbootstrap`: used to compile the SM8250 mainline kernel and firmware.

---

## 3. Kernel & Firmware Build (pmbootstrap)

1. **Initialize pmbootstrap:**
   ```sh
   pmbootstrap init
   # Work path: ~/.local/var/pmbootstrap
   # Channel: edge
   # Device: xiaomi-alioth
   ```

2. **Copy alioth package definitions into pmaports:**
   ```sh
   cp -r ~/pmaports-alioth/*-alioth ~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/
   ```

3. **Build kernel and firmware:**
   ```sh
   pmbootstrap build firmware-xiaomi-alioth
   pmbootstrap build linux-postmarketos-qcom-sm8250-alioth
   pmbootstrap build device-xiaomi-alioth
   pmbootstrap install
   ```

Artifact locations:
* `boot.img`: `~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/boot/boot.img`
* Kernel modules: `~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/lib/modules/6.19.6-pipa/`
* Firmware: `~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/lib/firmware/`

---

## 4. Preparing the Fedora Image

1. **Download Fedora KDE Mobile raw image:**
   ```sh
   curl -LO "https://download.fedoraproject.org/pub/fedora/linux/releases/44/Spins/aarch64/images/Fedora-KDE-Mobile-Disk-44-1.7.aarch64.raw.xz"
   unxz Fedora-KDE-Mobile-Disk-44-1.7.aarch64.raw.xz
   ```

2. **Mount the Btrfs root subvolume:**
   ```sh
   sudo losetup -Pf Fedora-KDE-Mobile-Disk-44-1.7.aarch64.raw
   sudo mkdir -p /mnt/fedora
   sudo mount -o subvol=root /dev/loop0p3 /mnt/fedora
   ```

3. **Inject alioth kernel modules & firmware:**
   ```sh
   # Kernel modules
   sudo cp -r ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/lib/modules/6.19.6-pipa \
     /mnt/fedora/usr/lib/modules/

   # Firmware
   sudo cp -r ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/lib/firmware/* \
     /mnt/fedora/usr/lib/firmware/

   # ALSA Audio UCM profiles
   sudo mkdir -p /mnt/fedora/usr/share/alsa/ucm2/Xiaomi/alioth /mnt/fedora/usr/share/alsa/ucm2/conf.d/sm8250
   sudo cp ~/pmaports-alioth/device-xiaomi-alioth/alsa-ucm-conf/*.conf \
     /mnt/fedora/usr/share/alsa/ucm2/Xiaomi/alioth/
   sudo ln -sf ../../Xiaomi/alioth/alioth.conf \
     /mnt/fedora/usr/share/alsa/ucm2/conf.d/sm8250/xiaomi-alioth.conf

   # Sensor udev rules
   sudo cp ~/pmaports-alioth/device-xiaomi-alioth/81-libssc-xiaomi-alioth.rules \
     /mnt/fedora/usr/lib/udev/rules.d/
   ```

4. **Fix `/etc/fstab` (prevent systemd emergency mode):**
   Fedora raw images mount `/boot` and `/boot/efi` by UUID. Since only the root partition is flashed to `userdata`, these mounts must be commented out:
   ```sh
   sudo sed -i '/\/boot/s/^/#/' /mnt/fedora/etc/fstab
   ```

5. **Set Root Password & SSH Access:**
   Fedora raw images lock the root account (`root:!`), causing `sulogin` to lock the console on boot:
   ```sh
   # Set root password to "fedora"
   HASH=$(openssl passwd -6 fedora)
   sudo sed -i "s|^root:!:[^:]*|root:${HASH}:20565|" /mnt/fedora/etc/shadow

   # Copy host SSH key for automatic login
   sudo mkdir -p /mnt/fedora/root/.ssh
   sudo cp ~/.ssh/id_*.pub /mnt/fedora/root/.ssh/authorized_keys
   sudo chmod 700 /mnt/fedora/root/.ssh
   sudo chmod 600 /mnt/fedora/root/.ssh/authorized_keys

   # Enable SSH daemon and generate host keys
   sudo ssh-keygen -t rsa -f /mnt/fedora/etc/ssh/ssh_host_rsa_key -N ""
   sudo ssh-keygen -t ecdsa -f /mnt/fedora/etc/ssh/ssh_host_ecdsa_key -N ""
   sudo ssh-keygen -t ed25519 -f /mnt/fedora/etc/ssh/ssh_host_ed25519_key -N ""
   sudo ln -sf /usr/lib/systemd/system/sshd.service /mnt/fedora/etc/systemd/system/multi-user.target.wants/sshd.service

   # Disable firewalld (unblock incoming USB SSH connections)
   sudo ln -sf /dev/null /mnt/fedora/etc/systemd/system/firewalld.service
   ```

6. **Set SELinux to Permissive:**
   ```sh
   sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /mnt/fedora/etc/selinux/config
   ```

7. **Configure USB Network Interface (`usb0`):**
   ```sh
   cat << 'EOF' | sudo tee /mnt/fedora/etc/NetworkManager/system-connections/usb0.nmconnection
   [connection]
   id=usb0
   uuid=e63fa6f2-1b15-4674-bf83-f6610ec3f312
   type=ethernet
   interface-name=usb0

   [ethernet]

   [ipv4]
   address1=172.16.42.1/24
   method=manual

   [ipv6]
   method=auto
   EOF
   sudo chmod 600 /mnt/fedora/etc/NetworkManager/system-connections/usb0.nmconnection
   ```

8. **Module Autoloading & Touchscreen Rules:**
   ```sh
   cat << 'EOF' | sudo tee /mnt/fedora/etc/modules-load.d/alioth.conf
   panel_samsung_ams667xx01
   qcom_common
   qcom_pil_info
   qcom_q6v5
   qcom_q6v5_pas
   spi_geni_qcom
   ft8756
   EOF

   cat << 'EOF' | sudo tee /mnt/fedora/etc/udev/rules.d/99-touchscreen.rules
   KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="*FT8756*", TAG+="uaccess", TAG+="seat", ENV{ID_INPUT}="1", ENV{ID_INPUT_TOUCHSCREEN}="1", MODE="0666"
   KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="*Focaltech*", TAG+="uaccess", TAG+="seat", ENV{ID_INPUT}="1", ENV{ID_INPUT_TOUCHSCREEN}="1", MODE="0666"
   EOF
   ```

9. **Set Filesystem Label:**
   ```sh
   sudo btrfs filesystem label /mnt/fedora pmOS_root
   ```

10. **Unmount & Convert to Android Sparse Image:**
    Fastboot on UFS devices requires Android Sparse format (`img2simg`):
    ```sh
    sudo sync
    sudo umount /mnt/fedora
    sudo img2simg /dev/loop0p3 ~/Downloads/fedora-rootfs.simg
    sudo losetup -d /dev/loop0
    ```

---

## 5. Customizing `boot.img`

`pmbootstrap`'s default `boot.img` contains hardcoded kernel cmdline arguments (`pmos_root_uuid` pointing to Alpine's UUID, and `pmos_rootfsopts=defaults`).

We must repack it with Fedora's UUID, `subvol=root`, and `selinux=0`:

1. **Unpack original `boot.img`:**
   ```sh
   mkdir -p /tmp/boot_unpack
   unpack_bootimg \
     --boot_img ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/boot/boot.img \
     --out /tmp/boot_unpack
   ```

2. **Repack with updated cmdline:**
   ```sh
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
     -o /tmp/boot_fedora.img

   rm -rf /tmp/boot_unpack
   ```

---

## 6. Flashing to Phone (Fastboot)

Reboot the phone into fastboot mode (Power + Volume Down):

```sh
# 1. Erase dtbo_b (critical: avoids conflict between Android OEM DTBO and mainline DTB)
fastboot erase dtbo_b

# 2. Flash customized boot image to boot_b
fastboot flash boot_b /tmp/boot_fedora.img

# 3. Flash Fedora sparse rootfs to userdata
fastboot flash userdata ~/Downloads/fedora-rootfs.simg

# 4. Set slot B active and reboot
fastboot set_active b
fastboot reboot
```
