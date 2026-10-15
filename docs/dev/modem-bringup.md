# 5G Cellular Modem (Qualcomm SDX55) Bring-Up Guide

Architecture, kernel drivers, firmware extraction, and userspace software stack for the Qualcomm Snapdragon X55 (SDX55) modem on the Xiaomi Poco F3 (`alioth`).

---

## 1. Flashless Modem Architecture on Alioth

The Snapdragon 870 SoC has no integrated cellular modem. Baseband connectivity is handled by a discrete external **Qualcomm SDX55** chip over PCIe (`pcie2`).

- **Flashless Baseband**: The SDX55 chip on alioth lacks onboard flash storage. All baseband firmware files, NV calibration items, and EFS partition images must be supplied by the host Linux system from UFS storage during boot.
- **Bus Protocols**:
  - Qualcomm MHI (Modem Host Interface) over PCIe.
  - QRTR (Qualcomm IPC Router) over MHI IPC-Router channels.
  - RmNet (Qualcomm cellular network aggregation protocol) for IP packet transport.

---

## 2. Required Kernel Drivers

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

DTS modem nodes are enabled by `0002-add-modem-sdx55m-support.patch`.

---

## 3. Userspace Components & Systemd Services

All integration files reside in `device-xiaomi-alioth/modem-services/`:

1. **`alioth-modem-firmware.service` / `alioth-modem-firmware.sh`**:
   - Reads modem partitions directly from UFS (`modemst1`, `modemst2`, `fsg`, `fsc`).
   - Populates baseband firmware files at `/lib/firmware/qcom/sdx55m/`.

2. **`tqftpserv.service`**:
   - Userspace TFTP daemon that serves firmware and EFS file requests initiated by the SDX55 modem over QRTR.
   - Prebuilt ARM64 binary provided at `device-xiaomi-alioth/modem-services/tqftpserv`.

3. **`alioth-modem.service`**:
   - Executes Sahara and EFS helpers (`sahara_srv.py`, `efs_srv.py`, `data_up.py`).
   - Configures the `rmnet_mhi0` network interface and maps QRTR communication ports.

4. **`alioth-sim-provision` & `alioth-switch-sim`**:
   - Controls the physical dual-SIM hardware switch on the Poco F3.
   - Points ModemManager to the appropriate primary control channel.

5. **Udev Rules**:
   - `77-mm-ignore-sdx55-extra.rules`: Prevents ModemManager from probing unsupported DIAG/trace ports.
   - `77-mm-sdx55-qrtr.rules`: Exposes the QRTR modem node to ModemManager.
