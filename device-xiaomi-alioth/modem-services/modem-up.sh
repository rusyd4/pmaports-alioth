#!/bin/bash
# Bring the SDX55 up from a cold boot and keep it up.
#
# Order matters and is not obvious:
#   - tqftpserv must be serving before the modem starts, or its subsystems never
#     come up and DMS answers DeviceNotReady forever (see HANDOFF 12.17);
#   - mhi_wwan_ctrl must be loaded before mhi_pci_generic, or the Sahara channel
#     has nobody to attach to;
#   - the Sahara and EFS servers must be waiting when the modem asks.
# The script ends by exec'ing the data session holder, because the packet session
# lives only as long as the QMI client that started it.
set -u

APN="${MODEM_APN:-internet.mts.ru}"
APN_USER="${MODEM_APN_USER:--}"
APN_PASS="${MODEM_APN_PASS:--}"
EP_IFACE=4
MUX_ID=1
EP_TYPE=3            # pcie (libqmi: PCIE=3, EMBEDDED=4)
LOG=/var/log/modem-up.log

log() { echo "[$(date +%T)] $*" | tee -a "$LOG"; }

mkdir -p /readwrite
: > "$LOG"

# tqftpserv and pd-mapper are services of their own here, and the unit orders
# us after them - starting a second copy only fights the first for the QRTR
# service number.
log "loading the transport modules"
modprobe qrtr_mhi
modprobe mhi_wwan_ctrl
modprobe mhi_net
modprobe rmnet

log "starting firmware servers"
setsid python3 -u /usr/local/bin/sahara_srv.py >> "$LOG" 2>&1 &
setsid python3 -u /usr/local/bin/efs_srv.py    >> "$LOG" 2>&1 &
sleep 1

log "powering the modem up"
modprobe mhi_pci_generic sdx_health=0 sdx_rpm=0

for i in $(seq 1 90); do
    [ -e /dev/wwan0qmi0 ] && break
    sleep 2
done
[ -e /dev/wwan0qmi0 ] || { log "modem never reached mission mode"; exit 1; }
log "mission mode reached"

# the QMI services need a moment after mission mode
for i in $(seq 1 30); do
    qmicli -d qrtr://3 --dms-get-operating-mode >/dev/null 2>&1 && break
    sleep 2
done

log "enabling the radio"
qmicli -d qrtr://3 --dms-set-operating-mode=online >> "$LOG" 2>&1

# Cards, their application ids and the power cycle each one needs live in
# their own script: the slot watcher and the operator both need to do exactly
# this again, later, whenever a card is put in.
alioth-sim-provision || true

for i in $(seq 1 40); do
    qmicli -d qrtr://3 --nas-get-serving-system 2>/dev/null | grep -q "'registered'" && break
    sleep 3
done
log "registration: $(qmicli -d qrtr://3 --nas-get-serving-system 2>/dev/null |
                     grep -m1 'Registration state' | tr -d '\t')"

log "preparing the data path"
qmicli -d qrtr://3 --dpm-open-port="hw-data-ep-type=pcie,hw-data-ep-iface-number=$EP_IFACE,\
hw-data-rx-id=101,hw-data-tx-id=100" >> "$LOG" 2>&1
# The endpoint type is pcie everywhere - here, and in the WDS bind later.  In
# libqmi the enum reads PCIE=3, EMBEDDED=4, so the numeric 3 above is pcie, not
# embedded.  Get this wrong and QMAP stays off: the session then comes up with
# an address, but the downlink never reaches the host.
qmicli -d qrtr://3 --wda-set-data-format="link-layer-protocol=raw-ip,ul-protocol=qmap,\
dl-protocol=qmap,dl-datagram-max-size=31744,dl-max-datagrams=32,ep-type=pcie,\
ep-iface-number=$EP_IFACE" >> "$LOG" 2>&1

ip link set mhi_hwip0 up
ip link del rmnet0 2>/dev/null
ip link add rmnet0 link mhi_hwip0 type rmnet mux_id $MUX_ID
ip link set rmnet0 up mtu 1500

# The bearer itself is NetworkManager's job now: it drives ModemManager, and two
# owners of the same session only fight.  data_up.py stays around for bringing
# data up by hand when the GUI is out of the picture.

# ModemManager is started by systemd long before the modem exists, so it finds
# nothing; restarting it here is what makes the modem show up in the shell.
log "handing over to ModemManager"
systemctl restart ModemManager

# ModemManager cannot bring the bearer up on this modem yet: it decides the
# setup is non-multiplexed, and in that mode it never binds the WDS client, so
# Start Network answers InvalidOperation.  Until that is sorted out, raise the
# session ourselves - SMS, SIM and signal still go through ModemManager.
# ModemManager can drive the bearer with the patches in this tree, so this
# is off by default now; set MODEM_SELF_DATA=1 to raise the session by hand.
if [ "${MODEM_SELF_DATA:-1}" = "1" ]; then
    ip link set mhi_hwip0 up
    ip link del rmnet0 2>/dev/null
    ip link add rmnet0 link mhi_hwip0 type rmnet mux_id $MUX_ID
    ip link set rmnet0 up mtu 1500

    log "starting the data session"
    setsid python3 -u /usr/local/bin/data_up.py "$APN" "$APN_USER" "$APN_PASS" \
            $EP_IFACE $MUX_ID $EP_TYPE >> "$LOG" 2>&1 &

    for i in $(seq 1 40); do
        grep -q SETTINGS "$LOG" && break
        sleep 2
    done

    val() { grep -o "'$1': '[0-9.]*'" "$LOG" | tail -1 | sed "s/.*': '//;s/'//"; }
    IP=$(val ip); MASK=$(val mask); DNS1=$(val dns1); DNS2=$(val dns2)
    prefix_of() {
        local m=$1 bits=0 o
        for o in ${m//./ }; do
            while [ $o -gt 0 ]; do bits=$((bits + (o & 1))); o=$((o >> 1)); done
        done
        echo $bits
    }
    if [ -n "$IP" ]; then
        PLEN=$(prefix_of "${MASK:-255.255.255.248}")
        ip addr flush dev rmnet0
        ip addr add "$IP/$PLEN" dev rmnet0
        ip route add default dev rmnet0 metric 700 2>/dev/null
        for d in $DNS1 $DNS2; do
            grep -q "^nameserver $d\$" /etc/resolv.conf 2>/dev/null || \
                echo "nameserver $d" >> /etc/resolv.conf
        done
        log "data up: $IP/$PLEN via rmnet0, dns $DNS1 $DNS2"
    else
        log "data session did not come up"
    fi
fi

log "modem ready"
