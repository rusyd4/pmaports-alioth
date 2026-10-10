#!/bin/sh
SERIAL=$(grep -o "serialno=[^ ]*" /proc/cmdline | cut -d= -f2)
if [ -z "$SERIAL" ]; then
    SERIAL=$(cat /etc/machine-id 2>/dev/null || echo "alioth-default")
fi
BT_MAC=$(echo "${SERIAL}-BT" | sha256sum | awk '{printf("0200%010s\n", $1)}' | cut -c1-12 | sed 's/\(..\)/\1:/g' | sed '$s/:$//')

# Wait for hci0 to appear if needed
for i in $(seq 1 10); do
    if btmgmt config 2>&1 | grep -q "missing options: public-address"; then
        btmgmt --index 0 public-addr "$BT_MAC"
        break
    fi
    sleep 1
done

rfkill unblock bluetooth
