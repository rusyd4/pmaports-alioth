# Kernel Development & Configuration Guide (SM8250 / Alioth)

Technical guide for mainline Linux kernel packaging and configuration for the Xiaomi Poco F3 (`alioth`) on the Qualcomm SM8250 / Kona platform.

---

## 1. CPU Architecture & Virtual Addressing

The Poco F3 is powered by the Qualcomm Snapdragon 870 (SM8250-AC):
- **CPU**: 1x Kryo 585 Prime (Cortex-A77 @ 3.2GHz) + 3x Kryo 585 Gold (Cortex-A77 @ 2.42GHz) + 4x Kryo 585 Silver (Cortex-A55 @ 1.8GHz).
- **ID_AA64MMFR2_EL1**: Bits [19:16] = `0x0`, indicating the Cortex-A77 and Cortex-A55 cores support a maximum of **48-bit Virtual Addresses** and **do not support LVA (Large Virtual Addressing / 52-bit)**.

### Mandatory Defconfig Options:
```kconfig
CONFIG_ARM64_VA_BITS_48=y
CONFIG_ARM64_VA_BITS=48
CONFIG_PGTABLE_LEVELS=4
# CONFIG_ARM64_VA_BITS_52 is not set
```

---

## 2. Critical Boot Constraint: `CONFIG_EFI_ZBOOT`

The Android BootLoader (ABL) on the Poco F3 does not implement EFI protocols:
- If `CONFIG_EFI_ZBOOT=y` is enabled, the kernel is packaged inside an EFI stub PE wrapper.
- ABL jumps directly to the entry point without running the EFI decompression stub, causing the device to crash back to Fastboot immediately with no dmesg output.

**Mandatory Fix:**
```kconfig
# CONFIG_EFI_ZBOOT is not set
```
The kernel must be built as a standard raw `Image.gz` that ABL and initramfs decompress natively.

---

## 3. Built-in Drivers (`=y`)

The display panel, SPI bus, and touchscreen must be compiled built-in (`=y`) to initialize before userspace initramfs:
```kconfig
CONFIG_SPI_QCOM_GENI=y
CONFIG_DRM_PANEL_SAMSUNG_AMS667XX01=y
CONFIG_TOUCHSCREEN_FT8756=y
```

---

## 4. Compilation Workflow via pmbootstrap

Kernel packaging lives in `linux-postmarketos-qcom-sm8250-alioth/`:

```sh
# 1. Sync local repo changes into pmbootstrap cache
./update_folder.sh

# 2. Update checksums if patches or config changed
pmbootstrap checksum linux-postmarketos-qcom-sm8250-alioth

# 3. Pull updated APKBUILD back into the repo
./store_folder_in_repo.sh

# 4. Build kernel package
pmbootstrap build --lax linux-postmarketos-qcom-sm8250-alioth
```

*RAM Tip*: If kernel linking runs out of host memory, disable Link Time Optimization in defconfig (`CONFIG_LTO_NONE=y`).

---

## 5. Compiling Out-of-Tree Kernel Modules

To test a driver without rebuilding the entire kernel:
1. Install build packages: `apk add rsync make clang lld flex bison llvm perl findutils openssl-dev`.
2. Link build headers: `ln -sfn /path/to/kernel-headers /lib/modules/$(uname -r)/build`.
3. Compile module:
   ```sh
   make -C /lib/modules/$(uname -r)/build M=$(pwd) modules
   ```
