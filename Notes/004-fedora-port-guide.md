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

## 3. Prepare Fedora Rootfs

1. **Extract and mount the raw Fedora image**:
   ```sh
   unxz Fedora-KDE-Mobile-Disk-*.raw.xz
   sudo losetup -Pf Fedora-KDE-Mobile-Disk-*.raw
   sudo mkdir -p /mnt/fedora
   sudo mount -o subvol=root /dev/loop0p3 /mnt/fedora
   ```

2. **Copy kernel modules and device firmware**:
   ```sh
   sudo cp -r ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/lib/modules/* \
     /mnt/fedora/usr/lib/modules/

   sudo cp -r ~/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth/lib/firmware/* \
     /mnt/fedora/usr/lib/firmware/

   # ALSA Audio UCM profiles
   sudo mkdir -p /mnt/fedora/usr/share/alsa/ucm2/Xiaomi/alioth /mnt/fedora/usr/share/alsa/ucm2/conf.d/sm8250
   sudo cp ~/pmaports-alioth/device-xiaomi-alioth/alsa-ucm-conf/*.conf \
     /mnt/fedora/usr/share/alsa/ucm2/Xiaomi/alioth/
   sudo ln -sf ../../Xiaomi/alioth/alioth.conf \
     /mnt/fedora/usr/share/alsa/ucm2/conf.d/sm8250/xiaomi-alioth.conf
   ```

3. **Disable unused `/boot` mounts in `/etc/fstab`**:
   *(Fedora raw images mount `/boot` and `/boot/efi` by UUID. Since we only flash the root filesystem to userdata, comment them out to prevent a 90s systemd timeout / emergency mode)*:
   ```sh
   sudo sed -i '/\/boot/s/^/#/' /mnt/fedora/etc/fstab
   ```

4. **Unlock root account & Enable SSH**:
   *(Fedora raw images default to a locked root account `root:!`, which blocks emergency login)*:
   ```sh
   HASH=$(openssl passwd -6 fedora)
   sudo sed -i "s|^root:!:[^:]*|root:${HASH}:20565|" /mnt/fedora/etc/shadow

   # Copy host SSH key for convenient remote access
   sudo mkdir -p /mnt/fedora/root/.ssh
   sudo cp ~/.ssh/id_*.pub /mnt/fedora/root/.ssh/authorized_keys
   sudo chmod 700 /mnt/fedora/root/.ssh
   sudo chmod 600 /mnt/fedora/root/.ssh/authorized_keys

   # Enable SSH daemon and generate host keys
   sudo ssh-keygen -t rsa -f /mnt/fedora/etc/ssh/ssh_host_rsa_key -N ""
   sudo ssh-keygen -t ecdsa -f /mnt/fedora/etc/ssh/ssh_host_ecdsa_key -N ""
   sudo ssh-keygen -t ed25519 -f /mnt/fedora/etc/ssh/ssh_host_ed25519_key -N ""
   sudo ln -sf /usr/lib/systemd/system/sshd.service /mnt/fedora/etc/systemd/system/multi-user.target.wants/sshd.service

   # Disable firewalld (kernel lacks full desktop nftables set; prevents SSH blocking)
   sudo ln -sf /dev/null /mnt/fedora/etc/systemd/system/firewalld.service
   ```

5. **Disable Wi-Fi Power Saving**:
   *(Qualcomm ath11k chip drops incoming ARP/broadcast packets when sleeping; disabling power saving keeps Wi-Fi responsive)*:
   ```sh
   cat << 'EOF' | sudo tee /mnt/fedora/etc/NetworkManager/conf.d/wifi-powersave.conf
   [connection]
   wifi.powersave = 2
   EOF
   ```

6. **Enable Bluetooth & HID Keyboard Modules**:
   *(Autoload Bluetooth UART, QCA transport, and HIDP/UHID drivers for keyboards and mice)*:
   ```sh
   cat << 'EOF' | sudo tee /mnt/fedora/etc/modules-load.d/bluetooth.conf
   btqca
   hci_uart
   hidp
   uhid
   EOF
   ```

7. **Enable Bluetooth MAC Initialization Service**:
   *(Qualcomm QCA6390 controllers require an initial public MAC address to transition out of unconfigured state)*:
   ```sh
   cat << 'EOF' | sudo tee /mnt/fedora/usr/local/bin/alioth-bluetooth-init.sh
   #!/bin/sh
   SERIAL=$(grep -o "serialno=[^ ]*" /proc/cmdline | cut -d= -f2)
   if [ -z "$SERIAL" ]; then
       SERIAL=$(cat /etc/machine-id 2>/dev/null || echo "alioth-default")
   fi
   BT_MAC=$(echo "${SERIAL}-BT" | sha256sum | awk '{printf("0200%010s\n", $1)}' | cut -c1-12 | sed 's/\(..\)/\1:/g' | sed '$s/:$//')

   if btmgmt config 2>&1 | grep -q "missing options: public-address"; then
       btmgmt --index 0 public-addr "$BT_MAC"
   fi
   rfkill unblock bluetooth
   EOF
   sudo chmod +x /mnt/fedora/usr/local/bin/alioth-bluetooth-init.sh

   cat << 'EOF' | sudo tee /mnt/fedora/etc/systemd/system/alioth-bluetooth.service
   [Unit]
   Description=Initialize Alioth Bluetooth Controller MAC
   Before=bluetooth.service
   Wants=bluetooth.service

   [Service]
   Type=oneshot
   ExecStart=/usr/local/bin/alioth-bluetooth-init.sh
   RemainAfterExit=yes

   [Install]
   WantedBy=multi-user.target
   EOF
   sudo ln -sf /etc/systemd/system/alioth-bluetooth.service /mnt/fedora/etc/systemd/system/multi-user.target.wants/alioth-bluetooth.service
   ```

8. **Convert to Android Sparse image**:
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
