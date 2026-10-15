#!/usr/bin/env bash
# Build patched ModemManager RPM for Fedora alioth
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="${SCRIPT_DIR}/0001-alioth-sdx55-support.patch"

if [ ! -f "${PATCH_FILE}" ]; then
    echo "ERROR: Patch file not found: ${PATCH_FILE}" >&2
    exit 1
fi

echo "==> [1/4] Installing build requirements..."
sudo dnf install -y rpm-build dnf-plugins-core
sudo dnf builddep -y ModemManager

echo "==> [2/4] Downloading source RPM..."
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

cd "${WORK_DIR}"
dnf download --source ModemManager
rpm -ivh ModemManager-*.src.rpm

echo "==> [3/4] Applying Alioth SDX55 patch to spec..."
cp "${PATCH_FILE}" ~/rpmbuild/SOURCES/
SPEC_FILE=$(ls ~/rpmbuild/SPECS/ModemManager*.spec | head -n 1)

if ! grep -q "0001-alioth-sdx55-support.patch" "${SPEC_FILE}"; then
    sed -i '/^Source0:/a Patch999: 0001-alioth-sdx55-support.patch' "${SPEC_FILE}"
    sed -i 's/^Release:\s*\(.*\)/Release: \1.alioth1/' "${SPEC_FILE}"
fi

echo "==> [4/4] Building RPM packages..."
rpmbuild -bb "${SPEC_FILE}"

echo "==> Build complete! Output RPMs:"
ls -lh ~/rpmbuild/RPMS/*/*.rpm
