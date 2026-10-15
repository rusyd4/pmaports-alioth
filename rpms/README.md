# Custom RPM Drop Directory

Taruh package RPM hasil compile di folder ini (misal `ModemManager-*.rpm`, `ModemManager-glib-*.rpm`).
Script `prepare-fedora-rootfs.sh` otomatis:
1. Mengekstrak file RPM ke dalam target rootfs.
2. Menyimpan salinan `.rpm` di `/var/cache/rpms/`.
3. Menambahkan `ModemManager*` ke `excludepkgs` di `/etc/dnf/dnf.conf`.
