#!/bin/sh
# Put the SDX55's own firmware and NV where the Sahara server expects them.
#
# None of this is shipped in a package: qdsp6sw.mbn alone is 84 MB and is the
# same copy that already sits in the phone's modem partition, while the efs
# images are unique to the handset - they carry its IMEI and its calibration.
# So both are taken from the phone itself, once, on the first boot.
set -eu

FW=/lib/firmware/qcom/sdx55m
RPROC_FW=/lib/firmware/qcom/sm8250/xiaomi/alioth
part () {
    if [ -e "/dev/disk/by-partlabel/$1" ]; then
        readlink -f "/dev/disk/by-partlabel/$1"
    elif [ -e "/dev/disk/by-partlabel/${1%_a}_b" ]; then
        readlink -f "/dev/disk/by-partlabel/${1%_a}_b"
    fi
}

[ -s "$FW/qdsp6sw.mbn" ] || {
	mkdir -p /mnt/modem "$FW" "$RPROC_FW"
	# vfat, and without -t the mount ends up guessing fuseblk and fails
	mount -t vfat -o ro "$(part modem_a)" /mnt/modem
	cp -f /mnt/modem/image/sdx55m/* "$FW"/
	# The modem asks for these over TFTP while it starts; tqftpserv resolves
	# /readonly/firmware/image/... next to the remoteproc firmware.
	cp -rf /mnt/modem/image/modem_pr "$RPROC_FW"/
	umount /mnt/modem
	echo "firmware copied out of modem_a"
}

# What the sensor core needs, in the two places hexagonrpcd serves it from:
# the DSP's own libraries off the dsp partition, and the sensor registry and
# calibration out of persist.  The registry is per handset - it carries this
# phone's accelerometer and gyroscope offsets - so it cannot be packaged either.
SNS=/usr/share/qcom/sm8250/xiaomi/alioth
[ -d "$SNS/dsp" ] || {
	mkdir -p /mnt/dsp "$SNS/dsp"
	mount -o ro "$(part dsp_a)" /mnt/dsp
	cp -r /mnt/dsp/sdsp/* "$SNS/dsp"/
	umount /mnt/dsp
	echo "sensor DSP libraries copied out of dsp_a"
}

[ -d "$SNS/sensors" ] || {
	mkdir -p /mnt/persist "$SNS/sensors"
	mount -o ro "$(part persist)" /mnt/persist
	cp -r /mnt/persist/sensors/* "$SNS/sensors"/
	umount /mnt/persist
	echo "sensor registry copied out of persist"
}

# The Bluetooth NVM that linux-firmware ships is generic; the one on the phone's
# own bluetooth partition holds this handset's radio calibration.  The address
# field in it is empty either way - see alioth-bt-addr.
[ -s /lib/firmware/qca/htnv20.bin ] || {
	mkdir -p /mnt/bt /lib/firmware/qca
	mount -t vfat -o ro "$(part bluetooth_a)" /mnt/bt
	cp -f /mnt/bt/image/htnv20.bin /mnt/bt/image/htbtfw20.tlv /lib/firmware/qca/
	umount /mnt/bt
	echo "bluetooth firmware copied out of bluetooth_a"
}

# The efs*.bin shipped next to the images are placeholders - they say
# "IMGEFS- DUMMY-1" inside - and a modem fed those comes up in factory test mode
# with no IMEI.  The real thing lives in these partitions.
for n in 1 2 3; do
	[ -s "$FW/efs${n}_real.bin" ] && continue
	dd if="$(part "mdm1m9kefs$n")" of="$FW/efs${n}_real.bin" bs=1M status=none
	echo "efs${n}_real.bin taken from mdm1m9kefs$n"
done
