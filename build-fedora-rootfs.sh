#!/usr/bin/env bash
# Build prepared Fedora sparse rootfs image for alioth from raw image
set -euo pipefail

RAW_IMAGE="${1:-/home/agata/Downloads/Fedora-KDE-Mobile-Disk-44-1.7.aarch64.raw}"
OUT_IMAGE="${2:-fedora-rootfs.simg}"
MOUNT_DIR="/mnt/fedora"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo $0 ...)" >&2
    exit 1
fi

if [ ! -f "${RAW_IMAGE}" ]; then
    if [ -f "${RAW_IMAGE}.xz" ]; then
        echo "==> Decompressing ${RAW_IMAGE}.xz..."
        xz -dk -T0 "${RAW_IMAGE}.xz"
    else
        echo "ERROR: Raw image not found: ${RAW_IMAGE}" >&2
        exit 1
    fi
fi

echo "==> Attaching loop device..."
LOOP_DEV=$(losetup -Pf --show "${RAW_IMAGE}")
echo "    Attached to ${LOOP_DEV}"

cleanup() {
    echo "==> Cleaning up mounts and loop device..."
    if mountpoint -q "${MOUNT_DIR}"; then
        umount "${MOUNT_DIR}" || true
    fi
    losetup -d "${LOOP_DEV}" || true
}
trap cleanup EXIT

echo "==> Mounting root subvolume from ${LOOP_DEV}p3 to ${MOUNT_DIR}..."
mkdir -p "${MOUNT_DIR}"
mount -o subvol=root "${LOOP_DEV}p3" "${MOUNT_DIR}"

echo "==> Provisioning rootfs via prepare-fedora-rootfs.sh..."
"${REPO_DIR}/prepare-fedora-rootfs.sh" "${MOUNT_DIR}"

echo "==> Syncing files and unmounting..."
sync
umount "${MOUNT_DIR}"
sync
blockdev --flushbufs "${LOOP_DEV}p3" || true
losetup -d "${LOOP_DEV}" || true
sync

echo "==> Re-attaching read-only loop device for clean capture..."
LOOP_DEV=$(losetup -Pf --show --read-only "${RAW_IMAGE}")

echo "==> Generating Android sparse image: ${OUT_IMAGE}..."
img2simg "${LOOP_DEV}p3" "${REPO_DIR}/${OUT_IMAGE}"

if [ -n "${SUDO_USER:-}" ]; then
    chown "${SUDO_USER}:${SUDO_USER}" "${REPO_DIR}/${OUT_IMAGE}" || true
fi

echo "==> DONE! Successfully created ${REPO_DIR}/${OUT_IMAGE}"
