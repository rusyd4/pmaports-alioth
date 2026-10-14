#!/usr/bin/env bash
#
# Pre-boot preparation script for Fedora rootfs on Xiaomi Poco F3 (alioth)
# Applies all hardware configurations, drivers, audio boost, and bluetooth fixes
# directly into a mounted Fedora rootfs before flashing.
#

set -euo pipefail

ROOTFS="${1:-/mnt/fedora}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
PMB_ROOTFS="${USER_HOME}/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth"

if [ ! -d "${ROOTFS}/usr" ]; then
    echo "ERROR: ${ROOTFS} does not appear to be a mounted rootfs!" >&2
    echo "Usage: sudo $0 /path/to/mounted/fedora/rootfs" >&2
    exit 1
fi

echo "==> [1/8] Injecting Kernel Modules & Device Firmware..."
mkdir -p "${ROOTFS}/usr/lib/modules" "${ROOTFS}/usr/lib/firmware"
LATEST_KERNEL_APK=$(ls -t "${USER_HOME}"/.local/var/pmbootstrap/packages/edge/aarch64/linux-postmarketos-qcom-sm8250-alioth-*.apk 2>/dev/null | head -n 1 || true)
if [ -n "${LATEST_KERNEL_APK}" ] && [ -f "${LATEST_KERNEL_APK}" ]; then
    echo "    Extracting latest modules from ${LATEST_KERNEL_APK}..."
    tar -zxf "${LATEST_KERNEL_APK}" -C "${ROOTFS}/usr" lib/modules
elif [ -d "${PMB_ROOTFS}/lib/modules" ]; then
    cp -r "${PMB_ROOTFS}"/lib/modules/* "${ROOTFS}/usr/lib/modules/"
fi

if [ -d "${PMB_ROOTFS}/lib/firmware" ]; then
    cp -r "${PMB_ROOTFS}"/lib/firmware/* "${ROOTFS}/usr/lib/firmware/"
fi

echo "==> [2/8] Injecting Audio UCM2 Profiles & Calibrated ALSA State..."
mkdir -p "${ROOTFS}/usr/share/alsa/ucm2/Xiaomi/alioth"
mkdir -p "${ROOTFS}/usr/share/alsa/ucm2/conf.d/sm8250"
mkdir -p "${ROOTFS}/usr/share/alsa/ucm2/conf.d/xiaomialioth"
mkdir -p "${ROOTFS}/usr/share/alsa/ucm2/conf.d/xiaomi-alioth"
mkdir -p "${ROOTFS}/var/lib/alsa"

cp "${REPO_DIR}"/device-xiaomi-alioth/alsa-ucm-conf/*.conf "${ROOTFS}/usr/share/alsa/ucm2/Xiaomi/alioth/"
ln -sf ../../Xiaomi/alioth/alioth.conf "${ROOTFS}/usr/share/alsa/ucm2/conf.d/sm8250/xiaomi-alioth.conf"
ln -sf ../../Xiaomi/alioth/alioth.conf "${ROOTFS}/usr/share/alsa/ucm2/conf.d/sm8250/xiaomialioth.conf"
ln -sf ../../Xiaomi/alioth/alioth.conf "${ROOTFS}/usr/share/alsa/ucm2/conf.d/xiaomialioth/xiaomialioth.conf"
ln -sf ../../Xiaomi/alioth/alioth.conf "${ROOTFS}/usr/share/alsa/ucm2/conf.d/xiaomi-alioth/xiaomi-alioth.conf"

if [ -f "${REPO_DIR}/device-xiaomi-alioth/asound.state" ]; then
    cp "${REPO_DIR}/device-xiaomi-alioth/asound.state" "${ROOTFS}/var/lib/alsa/asound.state"
fi

echo "==> [3/8] Setting up Bluetooth Controller Service & Autoload Modules..."
mkdir -p "${ROOTFS}/usr/local/bin" "${ROOTFS}/etc/systemd/system/multi-user.target.wants" "${ROOTFS}/etc/modules-load.d"
cp "${REPO_DIR}/device-xiaomi-alioth/alioth-bluetooth-init.sh" "${ROOTFS}/usr/local/bin/"
chmod +x "${ROOTFS}/usr/local/bin/alioth-bluetooth-init.sh"
cp "${REPO_DIR}/device-xiaomi-alioth/alioth-bluetooth.service" "${ROOTFS}/etc/systemd/system/"
ln -sf /etc/systemd/system/alioth-bluetooth.service "${ROOTFS}/etc/systemd/system/multi-user.target.wants/alioth-bluetooth.service"
cp "${REPO_DIR}/device-xiaomi-alioth/bluetooth-modules.conf" "${ROOTFS}/etc/modules-load.d/bluetooth.conf"

echo "==> [4/8] Applying Network & Sensor Configuration..."
mkdir -p "${ROOTFS}/etc/NetworkManager/conf.d" "${ROOTFS}/usr/lib/udev/rules.d"
cp "${REPO_DIR}/device-xiaomi-alioth/wifi-powersave.conf" "${ROOTFS}/etc/NetworkManager/conf.d/"
cp "${REPO_DIR}/device-xiaomi-alioth/81-libssc-xiaomi-alioth.rules" "${ROOTFS}/usr/lib/udev/rules.d/"

echo "==> [5/8] Setting up SDX55 Modem Daemons & Services..."
mkdir -p "${ROOTFS}/usr/local/bin" "${ROOTFS}/usr/local/lib/tqftpserv" "${ROOTFS}/etc/systemd/system/multi-user.target.wants" "${ROOTFS}/etc/udev/rules.d"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/"*.py "${ROOTFS}/usr/local/bin/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/"*.sh "${ROOTFS}/usr/local/bin/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/alioth-sim-provision" "${ROOTFS}/usr/local/bin/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/tqftpserv" "${ROOTFS}/usr/local/bin/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/"*.so* "${ROOTFS}/usr/local/lib/tqftpserv/"
chmod +x "${ROOTFS}/usr/local/bin/"*

cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/alioth-modem-firmware.service" "${ROOTFS}/etc/systemd/system/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/alioth-modem.service" "${ROOTFS}/etc/systemd/system/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/tqftpserv.service" "${ROOTFS}/etc/systemd/system/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/77-mm-ignore-sdx55-extra.rules" "${ROOTFS}/etc/udev/rules.d/"

ln -sf ../alioth-modem-firmware.service "${ROOTFS}/etc/systemd/system/multi-user.target.wants/alioth-modem-firmware.service"
ln -sf ../tqftpserv.service "${ROOTFS}/etc/systemd/system/multi-user.target.wants/tqftpserv.service"
ln -sf ../alioth-modem.service "${ROOTFS}/etc/systemd/system/multi-user.target.wants/alioth-modem.service"

mkdir -p "${ROOTFS}/usr/share/alioth-modem"
ln -sf /usr/local/bin/sahara_srv.py "${ROOTFS}/usr/share/alioth-modem/sahara_srv.py"
ln -sf /usr/local/bin/efs_srv.py "${ROOTFS}/usr/share/alioth-modem/efs_srv.py"
ln -sf /usr/local/bin/data_up.py "${ROOTFS}/usr/share/alioth-modem/data_up.py"

echo "==> [6/8] Configuring Root Credentials & SSH Access (enabled by default)..."
HASH=$(openssl passwd -6 fedora)
sed -i "s|^root:!:[^:]*|root:${HASH}:20565|" "${ROOTFS}/etc/shadow"

mkdir -p "${ROOTFS}/root/.ssh"
if compgen -G "${USER_HOME}/.ssh/id_*.pub" > /dev/null; then
    cat "${USER_HOME}"/.ssh/id_*.pub > "${ROOTFS}/root/.ssh/authorized_keys"
    chmod 700 "${ROOTFS}/root/.ssh"
    chmod 600 "${ROOTFS}/root/.ssh/authorized_keys"
fi

mkdir -p "${ROOTFS}/etc/ssh/sshd_config.d"
for type in rsa ecdsa ed25519; do
    if [ ! -f "${ROOTFS}/etc/ssh/ssh_host_${type}_key" ]; then
        ssh-keygen -q -t "${type}" -f "${ROOTFS}/etc/ssh/ssh_host_${type}_key" -N ""
    fi
done

cat << 'EOF_SSHD' > "${ROOTFS}/etc/ssh/sshd_config.d/01-permitrootlogin.conf"
PermitRootLogin yes
PasswordAuthentication yes
EOF_SSHD

mkdir -p "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
mkdir -p "${ROOTFS}/etc/systemd/system/sockets.target.wants"
ln -sf /usr/lib/systemd/system/sshd.service "${ROOTFS}/etc/systemd/system/multi-user.target.wants/sshd.service"
ln -sf /usr/lib/systemd/system/sshd.socket "${ROOTFS}/etc/systemd/system/sockets.target.wants/sshd.socket"

mkdir -p "${ROOTFS}/etc/systemd/system-preset"
cat << 'EOF_PRESET' > "${ROOTFS}/etc/systemd/system-preset/00-alioth.preset"
enable sshd.service
enable sshd.socket
enable alioth-modem.service
enable tqftpserv.service
enable alioth-modem-firmware.service
enable alioth-bluetooth.service
EOF_PRESET

ln -sf /dev/null "${ROOTFS}/etc/systemd/system/firewalld.service"

echo "==> [7/8] Patching /etc/fstab..."
sed -i '/\/boot/s/^/#/' "${ROOTFS}/etc/fstab"

echo "==> [7/7] Pre-boot configuration complete for ${ROOTFS}!"
