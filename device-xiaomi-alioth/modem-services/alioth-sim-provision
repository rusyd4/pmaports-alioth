#!/bin/bash
# Provision whatever SIM cards are in the phone right now, and get their
# applications to 'ready'.
#
# Run by the bring-up service at boot, by the slot watcher when a card is put in
# or taken out, and by hand whenever the modem has lost track of a card:
#
#     alioth-sim-provision
#
# Exit status is 0 when something was provisioned and 1 when every card was
# already up, so a caller can decide whether ModemManager needs a restart.
set -u

DEV=qrtr://3
LOG=${MODEM_LOG:-/var/log/modem-up.log}
log () { echo "[$(date +%T)] $*" | tee -a "$LOG"; }

# "Slot [1]:" has to be matched literally: as a regex the brackets are a
# character class and nothing ever matches.
slot_aid () {
    qmicli -d $DEV --uim-get-card-status 2>/dev/null |
        awk -v want="Slot [$1]:" '
            index($0, want) {inslot=1; next}
            inslot && index($0, "Slot [") {exit}
            inslot && /usim/ {u=1}
            inslot && u && /^\t+A0:/ {gsub(/[: \t]/,""); print; exit}'
}

sim_ready () {
    qmicli -d $DEV --uim-get-card-status 2>/dev/null |
        awk -v want="Slot [$1]:" '
            index($0, want) {inslot=1; next}
            inslot && index($0, "Slot [") {exit}
            inslot && /Application state: .ready./ {print "ready"; exit}'
}

# A card that has just been powered up sits in application state 'detected' and
# never initialises by itself.  It reaches 'ready' only after the slot is power
# cycled, and only once a provisioning session is bound to it - power cycling
# before provisioning changes nothing.  Until the application is ready
# ModemManager sees no SIM at all and gives up with "sim-missing", even though
# the card status says 'present'.
power_cycle_slot () {
    local slot=$1 i
    [ -n "$(sim_ready "$slot")" ] && return 0
    log "slot $slot: power cycling the card"
    qmicli -d $DEV --uim-sim-power-off="$slot" >> "$LOG" 2>&1
    sleep 3
    qmicli -d $DEV --uim-sim-power-on="$slot" >> "$LOG" 2>&1
    sleep 8
    for i in $(seq 1 10); do
        [ -n "$(sim_ready "$slot")" ] && { log "slot $slot: application ready"; return 0; }
        sleep 3
    done
    log "slot $slot: application never became ready"
    return 1
}

# Whichever slots actually hold a card become the primary and secondary
# subscriptions, in order.  Assuming slot 1 is the primary breaks the moment
# there is only a card in slot 2 - and a dual SIM modem with one subscription
# unprovisioned confuses ModemManager into reprobing the modem forever.
#
# Each card has its own application id, and using the wrong one leaves the
# application stuck in 'detected' while libqmi reports a nonsensical "could not
# power off SIM".  Read the id out of the card status, per slot.
n=0
changed=1
for slot in 1 2; do
    aid=$(slot_aid "$slot")
    [ -n "$aid" ] || { log "slot $slot: no usim application"; continue; }
    n=$((n + 1))
    [ -n "$(sim_ready "$slot")" ] && { log "slot $slot: already ready"; continue; }
    case $n in
        1) type=primary-gw-provisioning ;;
        2) type=secondary-gw-provisioning ;;
    esac
    log "slot $slot: provisioning $type with aid $aid"
    qmicli -d $DEV --uim-change-provisioning-session=\
"session-type=$type,activate=yes,slot=$slot,aid=$aid" >> "$LOG" 2>&1
    power_cycle_slot "$slot"
    changed=0
done

[ "$n" -gt 0 ] || log "no SIM found in either slot"
exit $changed
