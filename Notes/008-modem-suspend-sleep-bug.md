# Bug: SDX55 Modem Disconnects After Wake-Up from Sleep (s2idle)

## 1. Problem Description

When the Xiaomi Poco F3 (`alioth`) wakes up from sleep (*system suspend* `s2idle`), cellular connectivity drops entirely:
- `mmcli -L` reports `No modems were found`.
- Network interfaces `mhi_hwip0` and `rmnet0` disappear from `ip a`.
- `ModemManager` releases all communication ports (`wwan0qmi0`, `wwan0mbim0`, `qrtr3`).

---

## 2. Analysis & Diagnostic Evidence (`dmesg`)

Kernel logs captured during suspend and resume:

```text
[ 1098.548548] PM: suspend entry (s2idle)
...
[ 1099.902157] PM: suspend exit
[ 1340.384239] mhi mhi0: Did not enter M0 state, MHI state: M3, PM state: M3->M0
[ 1340.384282] mhi-pci-generic 0002:01:00.0: failed to resume device: -5
[ 1340.384444] mhi-pci-generic 0002:01:00.0: device recovery started
[ 1340.391705] wwan wwan0: port wwan0qmi0 disconnected
...
[ 1343.464047] pcieport 0002:00:00.0: broken device, retraining non-functional downstream link at 2.5GT/s
[ 1344.468291] pcieport 0002:00:00.0: retraining failed
[ 1344.468681] mhi-pci-generic 0002:01:00.0: Recovery failed: -25
```

### Root Cause
1. **External PCIe Modem**: The SDX55 is linked via PCIe lane 2 (`1c10000.pcie`). In the current SM8250 mainline kernel, when the host enters `s2idle`, the PCIe root complex undergoes power/clock collapse.
2. **Failed M3 -> M0 State Transition**: The `mhi_pci_generic` driver puts the modem into state `M3` (`PCI_D3hot`) upon suspend. When the host resumes (`suspend exit`), the modem firmware fails to respond to the transition request back to `M0` (timeout, error `-5` / `-EIO`).
3. **Interface Teardown**: The failed resume triggers MHI `device recovery`, which unregisters and tears down all child devices (`wwan0qmi0`, `rmnet0`, and the QRTR node).
4. **Link Retraining Failure**: Standard downstream PCIe link retraining fails because the SDX55 chip requires a complete cold-boot sequence (SPMI PMIC warm-reset + 84 MB firmware re-flashing via Sahara + EFS synchronization).

---

## 3. Battery Drain Considerations

* Why keep suspend **enabled by default**?
  - `s2idle` deeply gates CPU cores and SoC power rails while the screen is off.
  - Completely disabling suspend keeps the CPU in standard idle (`WFI`/`cpuidle`), leading to significantly higher battery drain (~2-3x faster standby consumption when the screen is off).

---

## 4. Workarounds (Optional)

### Option A: Retain Default Behavior (Recommended for Battery Life)
Allow normal system suspend to maximize battery longevity. If the modem drops after long sleep periods, perform a quick reboot to reinitialize it:
```sh
reboot
```

### Option B: Disable System Suspend (24/7 Cellular Connectivity)
If the device serves as a hotspot/tethering unit or requires uninterrupted mobile data, system suspend can be masked. The screen will still turn off (*display blanking*), but the kernel will never enter `s2idle`:

```sh
# Mask suspend and sleep targets
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

To restore the default suspend behavior:
```sh
# Unmask suspend and sleep targets
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
```
