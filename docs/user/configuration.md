# User Configuration & Daily Usage Guide

Practical tips, hardware audio calibration, cellular networking, and system switching for the Xiaomi Poco F3 (`alioth`).

---

## 1. Audio Volume Calibration (CS35L41)

The Cirrus Logic CS35L41 hardware amplifiers default to conservative gain stages in ALSA:

### Boosting Speaker Volume
1. On the phone terminal, launch `alsamixer`:
   ```sh
   alsamixer
   ```
2. Press **F6** and select the Qualcomm sound card (sm8250).
3. Raise the following mixer sliders to maximum:
   - `RCV Analog PCM Volume`
   - `LCV Analog PCM Volume`
   - `RCV Digital PCM Volume`
   - `LCV Digital PCM Volume`
4. Persist the mixer state across reboots:
   ```sh
   sudo alsactl store
   ```
5. Alternatively, in **KDE Sound Settings**, enable **"Raise maximum volume" / "Allow volume over 100%"**.

---

## 2. 5G Cellular Networking & SDX55 Modem

The Qualcomm SDX55 modem is connected over PCIe and managed by `alioth-modem`, `tqftpserv`, and `alioth-modem-firmware` services.

### Checking Modem Status
```sh
mmcli -L
mmcli -m 0
```

### Switching Active SIM Slots
Poco F3 supports dual physical SIM cards. The mainline kernel routes cellular data to the active SIM slot:

- **Via GUI**:
  Open the Plasma Mobile application launcher → tap **"Switch to SIM 1"** or **"Switch to SIM 2"**.
- **Via CLI**:
  ```sh
  # Switch data to SIM 1
  sudo alioth-switch-sim 1

  # Switch data to SIM 2
  sudo alioth-switch-sim 2
  ```

---

## 3. Wi-Fi & Bluetooth

- **Wi-Fi**:
  Connect using Plasma Mobile settings or terminal:
  ```sh
  nmtui
  # or
  nmcli dev wifi connect "SSID_NAME" password "WIFI_PASSWORD"
  ```
- **Bluetooth**:
  The `alioth-bluetooth.service` unit starts automatically at boot and loads firmware via `/usr/local/bin/alioth-bluetooth-init.sh`. Check controller status:
  ```sh
  bluetoothctl show
  ```

---

## 4. SSH Remote Access

Fedora images provisioned via `prepare-fedora-rootfs.sh` automatically enable the SSH daemon:
- **Port**: 22
- **User**: `root`
- **Default password**: `fedora`
- **SSH Key**: The host PC's public keys (`~/.ssh/id_*.pub`) are automatically injected into `/root/.ssh/authorized_keys`.

Connect from your PC over USB tethering or local Wi-Fi:
```sh
ssh root@172.16.42.1
# or via local Wi-Fi IP
ssh root@192.168.x.x
```

---

## 5. System Updates (DNF Safety)

The rootfs provisioning script automatically excludes kernel and ModemManager packages from DNF in `/etc/dnf/dnf.conf` (`excludepkgs=kernel* ModemManager*`). This prevents `dnf upgrade` from overwriting the custom alioth mainline kernel with upstream generic Fedora aarch64 kernels.
