# Fedora Rootfs Automation & Provisioning Guide

Technical documentation for the automated Fedora ARM64 rootfs preparation scripts (`prepare-fedora-rootfs.sh` and `build-fedora-rootfs.sh`) for the Xiaomi Poco F3.

---

## 1. Automation Workflow

To boot Fedora directly on the Poco F3, a generic upstream ARM64 disk image (`Fedora-KDE-Mobile-Disk-*.raw`) must be provisioned with hardware configurations and drivers before being written to UFS storage.

### Primary Scripts:
1. **`build-fedora-rootfs.sh [raw_image] [out_simg]`**:
   - Attaches the raw disk image to a loopback device (`losetup -Pf`).
   - Mounts the Btrfs root subvolume (`-o subvol=root /dev/loopXp3 /mnt/fedora`).
   - Runs `prepare-fedora-rootfs.sh /mnt/fedora`.
   - Converts the provisioned partition to an Android Sparse Image (`img2simg`).
2. **`prepare-fedora-rootfs.sh [rootfs_mount_dir]`**:
   - Executes 8 distinct provisioning stages directly into the mounted root filesystem.

---

## 2. The 8 Provisioning Stages

1. **Kernel Modules & Firmware**:
   - Extracts kernel modules from the newest pmbootstrap APK (`linux-postmarketos-qcom-sm8250-alioth-*.apk`).
   - Copies non-free firmware from the local pmbootstrap rootfs (`/lib/firmware`).
   - Runs `depmod -a -b ${ROOTFS}` for all detected kernel module trees.

2. **Audio UCM2 & ALSA State**:
   - Copies `alioth.conf` and `HiFi.conf` into `/usr/share/alsa/ucm2/Xiaomi/alioth/`.
   - Creates symlinks for SM8250 sound card naming variations.
   - Injects the calibrated `asound.state` into `/var/lib/alsa/asound.state`.

3. **Bluetooth Controller**:
   - Copies the hardware bring-up script `/usr/local/bin/alioth-bluetooth-init.sh`.
   - Enables the `alioth-bluetooth.service` systemd unit.
   - Deploys the module autoload file `bluetooth.conf`.

4. **Network, Sensor, & Plasma Mobile Tweaks**:
   - Disables Wi-Fi power save via `/etc/NetworkManager/conf.d/wifi-powersave.conf`.
   - Copies SSC sensor udev rules (`81-libssc-xiaomi-alioth.rules`).
   - Disables KWallet popups on Plasma Mobile (`kwalletrc`).
   - Preconfigures an automatic cellular data profile (`cellular.nmconnection`).

5. **Modem Daemons, Helpers, & SIM Switching**:
   - Installs Sahara and EFS Python daemons (`sahara_srv.py`, `efs_srv.py`, `data_up.py`).
   - Deploys prebuilt `tqftpserv` and `qbootctl` binaries.
   - Adds Plasma Mobile desktop shortcuts to toggle between SIM 1 and SIM 2.
   - Enables `alioth-modem.service`, `tqftpserv.service`, and `alioth-modem-firmware.service`.

6. **Root Credentials, SSH Access, & Systemd Watchdog Config**:
   - Sets default root password to `fedora`.
   - Injects the host user's SSH public keys (`~/.ssh/id_*.pub`) into `/root/.ssh/authorized_keys`.
   - Generates SSH host keys (RSA, ECDSA, ED25519) and enables `sshd.service`.
   - Injects `/etc/systemd/system.conf.d/00-alioth-watchdog.conf` to disable `RebootWatchdogSec` and `ShutdownWatchdogSec` (preventing SM8250 hardware WDT bite hangs caused by 32s limit vs systemd 10min default) and lowers `DefaultTimeoutStopSec` to 10s.
   - Installs custom RPMs (such as patched ModemManager) if present in `rpms/`.

7. **Patching `/etc/fstab`**:
   - Comments out the upstream Fedora `/boot` entry to prevent mounting conflicts with Android A/B boot partitions.

8. **Package Protection in DNF**:
   - Injects `/etc/dnf/dnf.conf.d/00-alioth-exclude.conf` and updates `/etc/dnf/dnf.conf` with `exclude=kernel* ModemManager*` and `excludepkgs=kernel* ModemManager*` to protect custom alioth kernel and ModemManager packages across DNF 4 and DNF 5 during system upgrades.
