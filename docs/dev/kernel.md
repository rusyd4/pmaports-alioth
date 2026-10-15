# Kernel Development & Configuration Guide (SM8250 / Alioth)

Panduan teknis kernel mainline Linux untuk Xiaomi Poco F3 (`alioth`) pada platform Qualcomm SM8250 / Kona.

---

## 1. Arsitektur CPU & Memori Virtual

Poco F3 ditenagai oleh Qualcomm Snapdragon 870 (SM8250-AC):
- **CPU**: 1x Kryo 585 Prime (Cortex-A77 @ 3.2GHz) + 3x Kryo 585 Gold (Cortex-A77 @ 2.42GHz) + 4x Kryo 585 Silver (Cortex-A55 @ 1.8GHz).
- **ID_AA64MMFR2_EL1**: Bit [19:16] = `0x0`, menandakan core Cortex-A77 / A55 hanya mendukung maksimal **48-bit Virtual Addresses** dan **tidak mendukung LVA (Large Virtual Addressing / 52-bit)**.

### Konfigurasi Wajib defconfig:
```kconfig
CONFIG_ARM64_VA_BITS_48=y
CONFIG_ARM64_VA_BITS=48
CONFIG_PGTABLE_LEVELS=4
# CONFIG_ARM64_VA_BITS_52 is not set
```

---

## 2. Masalah Kritis: `CONFIG_EFI_ZBOOT`

Bootloader Android (ABL - Android BootLoader) pada Poco F3 tidak mengimplementasikan protokol EFI standar.
- Jika `CONFIG_EFI_ZBOOT=y` diaktifkan, kernel dikompresi ke dalam EFI stub PE wrapper.
- ABL melompat langsung ke entry point tanpa mengeksekusi decompresor EFI stub, menyebabkan device langsung crash kembali ke Fastboot tanpa output dmesg.

**Solusi Wajib:**
```kconfig
# CONFIG_EFI_ZBOOT is not set
```
Kernel dibangun sebagai raw image `Image.gz` standar yang dapat didekompresi langsung oleh ABL/initramfs.

---

## 3. Driver Built-in (`=y`)

Agar layar dan display server berfungsi saat boot sebelum initramfs memuat modul:
```kconfig
CONFIG_SPI_QCOM_GENI=y
CONFIG_DRM_PANEL_SAMSUNG_AMS667XX01=y
CONFIG_TOUCHSCREEN_FT8756=y
```

---

## 4. Alur Kerja Kompilasi via pmbootstrap

Direktori package kernel berada di `linux-postmarketos-qcom-sm8250-alioth/`.

```sh
# 1. Sinkronisasi perubahan lokal ke pmbootstrap cache
./update_folder.sh

# 2. Update checksum package APKBUILD jika ada perubahan patch atau config
pmbootstrap checksum linux-postmarketos-qcom-sm8250-alioth

# 3. Ambil kembali APKBUILD terupdate ke repo
./store_folder_in_repo.sh

# 4. Build kernel package
pmbootstrap build --lax linux-postmarketos-qcom-sm8250-alioth
```

*Tip RAM*: Jika kompilasi kernel gagal kehabisan RAM saat proses linking, nonaktifkan LTO (Link Time Optimization) pada defconfig (`CONFIG_LTO_NONE=y`).

---

## 5. Kompilasi Modul Kernel Out-of-Tree

Jika menguji driver baru tanpa rebuild full kernel:
1. Pasang paket build: `apk add rsync make clang lld flex bison llvm perl findutils openssl-dev`.
2. Link build header: `ln -sfn /path/to/kernel-headers /lib/modules/$(uname -r)/build`.
3. Kompilasi modul:
   ```sh
   make -C /lib/modules/$(uname -r)/build M=$(pwd) modules
   ```
