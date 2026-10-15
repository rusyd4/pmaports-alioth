# Wi-Fi & Bluetooth Bring-Up Guide (QCA6390)

Technical documentation for Qualcomm Atheros QCA6390 (Wi-Fi 6 + Bluetooth 5.1) bring-up on the Xiaomi Poco F3 (`alioth`).

---

## 1. Hardware Interface Architecture

The QCA6390 chip connects to the SM8250 SoC through two separate hardware buses:
1. **Wi-Fi**: PCIe Gen 2 via the Qualcomm MHI bus (`ath11k_pci`).
2. **Bluetooth**: High-speed serial UART (`ttyMSM1`) controlled by Qualcomm HCI protocol (`hci_qcomm_init`).

---

## 2. Critical Wi-Fi Challenge: MHI Power State Transitions

In early mainline kernels, initializing the QCA6390 WLAN chip often hit timeouts or bus lockups during power state transitions (M0 → M3 → M0).

### Root Cause:
Aggressive MHI state transitions caused PCIe registers to lose clock synchronization before WLAN firmware initialization finished.

### Solution:
Scope MHI transitions and increase timeout margins in the `ath11k` driver and `mhi_bus` subsystem. Detailed in commit `112dbb63c12cb6379efd5028fc68bd5c83460fea` and patch `0003-wifi-qca6390-bringup.patch`.

---

## 3. Wi-Fi Driver Configuration

```kconfig
CONFIG_ATH11K=m
CONFIG_ATH11K_PCI=m
CONFIG_ATH11K_DEBUG=y
CONFIG_QRTR=m
```

### Power Save Optimization
NetworkManager defaults to aggressive Wi-Fi power saving, which causes periodic connection drops on the QCA6390. A fix is deployed via `/etc/NetworkManager/conf.d/wifi-powersave.conf`:
```ini
[connection]
wifi.powersave = 2
```
*(Value 2 = Disables power saving for maximum link stability).*

---

## 4. Bluetooth Initialization

Bluetooth is managed by `alioth-bluetooth.service` and the hardware initialization script `/usr/local/bin/alioth-bluetooth-init.sh`:

1. Loads the `hci_uart` module.
2. Unblocks RFKILL for the Bluetooth controller.
3. Uploads the QCA6390 RAM patch and ramps UART baud rate:
   ```sh
   hci_qcomm_init -e -p 2 -s 3000000 /dev/ttyMSM1
   ```
4. Starts standard BlueZ `bluetoothd`.
