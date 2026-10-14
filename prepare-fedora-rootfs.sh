#!/usr/bin/env bash
#
# Pre-boot preparation script for Fedora rootfs on Xiaomi Poco F3 (alioth)
# Applies all hardware configurations, drivers, audio boost, and bluetooth fixes
# directly into a mounted Fedora rootfs before flashing.
#

set -euo pipefail

ROOTFS="${1:-/mnt/fedora}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PMB_ROOTFS="${HOME}/.local/var/pmbootstrap/chroot_rootfs_xiaomi-alioth"

if [ ! -d "${ROOTFS}/usr" ]; then
    echo "ERROR: ${ROOTFS} does not appear to be a mounted rootfs!" >&2
    echo "Usage: sudo $0 /path/to/mounted/fedora/rootfs" >&2
    exit 1
fi

echo "==> [1/7] Injecting Kernel Modules & Device Firmware..."
mkdir -p "${ROOTFS}/usr/lib/modules" "${ROOTFS}/usr/lib/firmware"
cp -r "${PMB_ROOTFS}"/lib/modules/* "${ROOTFS}/usr/lib/modules/"
cp -r "${PMB_ROOTFS}"/lib/firmware/* "${ROOTFS}/usr/lib/firmware/"

echo "==> [2/7] Injecting Audio UCM2 Profiles & Calibrated ALSA State..."
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

echo "==> [3/7] Setting up Bluetooth Controller Service & Autoload Modules..."
mkdir -p "${ROOTFS}/usr/local/bin" "${ROOTFS}/etc/systemd/system/multi-user.target.wants" "${ROOTFS}/etc/modules-load.d"
cp "${REPO_DIR}/device-xiaomi-alioth/alioth-bluetooth-init.sh" "${ROOTFS}/usr/local/bin/"
chmod +x "${ROOTFS}/usr/local/bin/alioth-bluetooth-init.sh"
cp "${REPO_DIR}/device-xiaomi-alioth/alioth-bluetooth.service" "${ROOTFS}/etc/systemd/system/"
ln -sf /etc/systemd/system/alioth-bluetooth.service "${ROOTFS}/etc/systemd/system/multi-user.target.wants/alioth-bluetooth.service"
cp "${REPO_DIR}/device-xiaomi-alioth/bluetooth-modules.conf" "${ROOTFS}/etc/modules-load.d/bluetooth.conf"

echo "==> [4/7] Applying Network & Sensor Configuration..."
mkdir -p "${ROOTFS}/etc/NetworkManager/conf.d" "${ROOTFS}/usr/lib/udev/rules.d"
cp "${REPO_DIR}/device-xiaomi-alioth/wifi-powersave.conf" "${ROOTFS}/etc/NetworkManager/conf.d/"
cp "${REPO_DIR}/device-xiaomi-alioth/81-libssc-xiaomi-alioth.rules" "${ROOTFS}/usr/lib/udev/rules.d/"

echo "==> [5/8] Setting up SDX55 Modem Daemons & Services..."
mkdir -p "${ROOTFS}/usr/local/bin" "${ROOTFS}/etc/systemd/system/multi-user.target.wants" "${ROOTFS}/etc/udev/rules.d"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/sahara_srv.py" "${ROOTFS}/usr/local/bin/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/efs_srv.py" "${ROOTFS}/usr/local/bin/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/data_up.py" "${ROOTFS}/usr/local/bin/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/diagprobe.py" "${ROOTFS}/usr/local/bin/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/modem-up.sh" "${ROOTFS}/usr/local/bin/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/alioth-sim-provision" "${ROOTFS}/usr/local/bin/"
chmod +x "${ROOTFS}/usr/local/bin/"*.py "${ROOTFS}/usr/local/bin/"*.sh "${ROOTFS}/usr/local/bin/alioth-sim-provision"

cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/alioth-modem.service" "${ROOTFS}/etc/systemd/system/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/tqftpserv.service" "${ROOTFS}/etc/systemd/system/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/77-mm-ignore-sdx55-extra.rules" "${ROOTFS}/etc/udev/rules.d/"

ln -sf /etc/systemd/system/alioth-modem.service "${ROOTFS}/etc/systemd/system/multi-user.target.wants/alioth-modem.service"
ln -sf /etc/systemd/system/tqftpserv.service "${ROOTFS}/etc/systemd/system/multi-user.target.wants/tqftpserv.service"

mkdir -p "${ROOTFS}/usr/share/alioth-modem"
ln -sf /usr/local/bin/sahara_srv.py "${ROOTFS}/usr/share/alioth-modem/sahara_srv.py"
ln -sf /usr/local/bin/efs_srv.py "${ROOTFS}/usr/share/alioth-modem/efs_srv.py"
ln -sf /usr/local/bin/data_up.py "${ROOTFS}/usr/share/alioth-modem/data_up.py"

echo "==> [6/8] Configuring Root Credentials & SSH Access..."
HASH=$(openssl passwd -6 fedora)
sed -i "s|^root:!:[^:]*|root:${HASH}:20565|" "${ROOTFS}/etc/shadow"

mkdir -p "${ROOTFS}/root/.ssh"
if compgen -G "${HOME}/.ssh/id_*.pub" > /dev/null; then
    cat "${HOME}"/.ssh/id_*.pub > "${ROOTFS}/root/.ssh/authorized_keys"
    chmod 700 "${ROOTFS}/root/.ssh"
    chmod 600 "${ROOTFS}/root/.ssh/authorized_keys"
fi

mkdir -p "${ROOTFS}/etc/ssh"
for type in rsa ecdsa ed25519; do
    if [ ! -f "${ROOTFS}/etc/ssh/ssh_host_${type}_key" ]; then
        ssh-keygen -q -t "${type}" -f "${ROOTFS}/etc/ssh/ssh_host_${type}_key" -N ""
    fi
done
ln -sf /usr/lib/systemd/system/sshd.service "${ROOTFS}/etc/systemd/system/multi-user.target.wants/sshd.service"
ln -sf /dev/null "${ROOTFS}/etc/systemd/system/firewalld.service"

echo "==> [7/8] Patching /etc/fstab..."
sed -i '/\/boot/s/^/#/' "${ROOTFS}/etc/fstab"

echo "==> [7/7] Pre-boot configuration complete for ${ROOTFS}!"
