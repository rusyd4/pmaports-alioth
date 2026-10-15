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

for kv in $(ls "${ROOTFS}/usr/lib/modules" 2>/dev/null); do
    echo "    Updating module dependencies (depmod) for ${kv}..."
    depmod -a -b "${ROOTFS}" "${kv}" || true
done

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
mkdir -p "${ROOTFS}/etc/NetworkManager/conf.d" "${ROOTFS}/usr/lib/udev/rules.d" "${ROOTFS}/etc/NetworkManager/system-connections" "${ROOTFS}/etc/xdg"
cp "${REPO_DIR}/device-xiaomi-alioth/wifi-powersave.conf" "${ROOTFS}/etc/NetworkManager/conf.d/"
cp "${REPO_DIR}/device-xiaomi-alioth/81-libssc-xiaomi-alioth.rules" "${ROOTFS}/usr/lib/udev/rules.d/"

# Disable KWallet prompt on Plasma Mobile
cat << 'EOF_KWALLET' > "${ROOTFS}/etc/xdg/kwalletrc"
[Wallet]
Enabled=false
First Use=false
EOF_KWALLET

# Pre-configure generic cellular connection for ModemManager / NetworkManager
cat << 'EOF_NM_CELL' > "${ROOTFS}/etc/NetworkManager/system-connections/cellular.nmconnection"
[connection]
id=Cellular
uuid=353c57c8-7c00-407c-a3dd-01b24af2738f
type=gsm
interface-name=qrtr3
autoconnect=true

[gsm]
apn=internet

[ipv4]
method=auto

[ipv6]
method=auto
EOF_NM_CELL
chmod 600 "${ROOTFS}/etc/NetworkManager/system-connections/cellular.nmconnection"

echo "==> [5/8] Setting up SDX55 Modem Daemons & Services..."
mkdir -p "${ROOTFS}/usr/local/bin" "${ROOTFS}/etc/systemd/system/multi-user.target.wants" "${ROOTFS}/etc/udev/rules.d" "${ROOTFS}/etc/modules-load.d" "${ROOTFS}/usr/share/applications"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/"*.py "${ROOTFS}/usr/local/bin/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/"*.sh "${ROOTFS}/usr/local/bin/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/alioth-sim-provision" "${ROOTFS}/usr/local/bin/"
[ -f "${REPO_DIR}/device-xiaomi-alioth/modem-services/alioth-switch-sim" ] && \
    cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/alioth-switch-sim" "${ROOTFS}/usr/local/bin/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/tqftpserv" "${ROOTFS}/usr/local/bin/"
[ -f "${REPO_DIR}/device-xiaomi-alioth/modem-services/0001-alioth-sdx55-support.patch" ] && \
    cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/0001-alioth-sdx55-support.patch" "${ROOTFS}/usr/local/bin/"
chmod +x "${ROOTFS}/usr/local/bin/"*

# Plasma Mobile GUI shortcuts for switching SIM
cat << 'EOF_SIM1_DESKTOP' > "${ROOTFS}/usr/share/applications/alioth-sim1.desktop"
[Desktop Entry]
Name=Ganti ke SIM 1
Comment=Aktifkan data seluler pada Slot 1
Exec=/usr/local/bin/alioth-switch-sim 1
Icon=network-cellular
Terminal=false
Type=Application
Categories=Settings;System;
EOF_SIM1_DESKTOP

cat << 'EOF_SIM2_DESKTOP' > "${ROOTFS}/usr/share/applications/alioth-sim2.desktop"
[Desktop Entry]
Name=Ganti ke SIM 2
Comment=Aktifkan data seluler pada Slot 2
Exec=/usr/local/bin/alioth-switch-sim 2
Icon=network-cellular
Terminal=false
Type=Application
Categories=Settings;System;
EOF_SIM2_DESKTOP

cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/modem-modules.conf" "${ROOTFS}/etc/modules-load.d/modem.conf"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/alioth-modem-firmware.service" "${ROOTFS}/etc/systemd/system/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/alioth-modem.service" "${ROOTFS}/etc/systemd/system/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/tqftpserv.service" "${ROOTFS}/etc/systemd/system/"
cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/77-mm-ignore-sdx55-extra.rules" "${ROOTFS}/etc/udev/rules.d/"
[ -f "${REPO_DIR}/device-xiaomi-alioth/modem-services/77-mm-sdx55-qrtr.rules" ] && \
    cp "${REPO_DIR}/device-xiaomi-alioth/modem-services/77-mm-sdx55-qrtr.rules" "${ROOTFS}/etc/udev/rules.d/"

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

# Inject custom RPMs (e.g. ModemManager)
if compgen -G "${REPO_DIR}/rpms/*.rpm" > /dev/null || compgen -G "${REPO_DIR}/device-xiaomi-alioth/rpms/*.rpm" > /dev/null; then
    echo "    Injecting custom RPM packages into rootfs..."
    mkdir -p "${ROOTFS}/var/cache/rpms"
    for rpm in "${REPO_DIR}"/rpms/*.rpm "${REPO_DIR}"/device-xiaomi-alioth/rpms/*.rpm; do
        [ -f "$rpm" ] || continue
        echo "    -> $(basename "$rpm")"
        cp "$rpm" "${ROOTFS}/var/cache/rpms/"
        if command -v bsdtar >/dev/null 2>&1; then
            bsdtar --no-xattrs --no-fflags -xf "$rpm" -C "${ROOTFS}"
        elif command -v rpm2cpio >/dev/null 2>&1; then
            (cd "${ROOTFS}" && rpm2cpio "$rpm" | cpio -idm)
        fi
    done
fi

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

mkdir -p "${ROOTFS}/etc/systemd/system-preset"
cat << 'EOF_PRESET' > "${ROOTFS}/etc/systemd/system-preset/00-alioth.preset"
enable sshd.service
enable alioth-modem.service
enable tqftpserv.service
enable alioth-modem-firmware.service
enable alioth-bluetooth.service
EOF_PRESET

ln -sf /dev/null "${ROOTFS}/etc/systemd/system/firewalld.service"

echo "==> [7/8] Patching /etc/fstab..."
sed -i '/\/boot/s/^/#/' "${ROOTFS}/etc/fstab"

echo "==> [8/8] Blocking Fedora kernel and ModemManager packages in DNF..."
mkdir -p "${ROOTFS}/etc/dnf"
if [ -f "${ROOTFS}/etc/dnf/dnf.conf" ]; then
    grep -q "excludepkgs=.*kernel" "${ROOTFS}/etc/dnf/dnf.conf" || echo "excludepkgs=kernel*" >> "${ROOTFS}/etc/dnf/dnf.conf"
    grep -q "ModemManager" "${ROOTFS}/etc/dnf/dnf.conf" || sed -i '/excludepkgs=/ s/$/ ModemManager*/' "${ROOTFS}/etc/dnf/dnf.conf"
else
    printf "[main]\nexcludepkgs=kernel* ModemManager*\n" > "${ROOTFS}/etc/dnf/dnf.conf"
fi

echo "==> Configuration complete for ${ROOTFS}!"
