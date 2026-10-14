#!/usr/bin/env python3
"""Minimal DIAG client for the SDX55, enough to read the modem's own F3 log.

The modem refuses DMS SetOperatingMode(online) with DeviceNotReady and says
nothing over QMI about why.  DIAG is where it explains itself: F3 messages carry
the file, line and text of every complaint its subsystems make.

Framing is HDLC: CRC-16/X-25 over the payload, 0x7d escaping, 0x7e terminator.
"""
import binascii, os, struct, sys, time

PORT = "/dev/wwan0qcdm0"

DIAG_VERNO_F = 0x00
DIAG_EXT_MSG_CONFIG_F = 0x7D
MSG_EXPAND_CONF = 0x04          # set all runtime masks
DIAG_EXT_MSG_F = 0x79           # what F3 messages come back as
DIAG_EXT_MSG_TERSE_F = 0x92


def crc16(data):
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8408 if crc & 1 else crc >> 1
    return crc ^ 0xFFFF


def frame(payload):
    body = payload + struct.pack("<H", crc16(payload))
    out = bytearray()
    for b in body:
        if b in (0x7E, 0x7D):
            out += bytes([0x7D, b ^ 0x20])
        else:
            out.append(b)
    out.append(0x7E)
    return bytes(out)


def unframe(buf):
    """Split a stream on 0x7e and undo the escaping.  Returns (packets, rest)."""
    packets, rest = [], b""
    for chunk in buf.split(b"\x7e"):
        rest = chunk
        if not chunk:
            continue
        out = bytearray()
        esc = False
        for b in chunk:
            if esc:
                out.append(b ^ 0x20)
                esc = False
            elif b == 0x7D:
                esc = True
            else:
                out.append(b)
        if len(out) > 2:
            packets.append(bytes(out[:-2]))
    if buf.endswith(b"\x7e"):
        rest = b""
    return packets, rest


def main():
    fd = os.open(PORT, os.O_RDWR | os.O_NONBLOCK)
    print("opened %s" % PORT, flush=True)

    def send(p):
        os.write(fd, frame(p))

    def pump(seconds, want=None):
        buf = b""
        end = time.monotonic() + seconds
        seen = []
        while time.monotonic() < end:
            try:
                data = os.read(fd, 0x4000)
            except BlockingIOError:
                time.sleep(0.01)
                continue
            except OSError as e:
                print("read error: %s" % e, flush=True)
                break
            if not data:
                time.sleep(0.01)
                continue
            buf += data
            pkts, buf = unframe(buf)
            for p in pkts:
                seen.append(p)
                show(p)
                if want is not None and p and p[0] == want:
                    return seen
        return seen

    def show(p):
        if not p:
            return
        cmd = p[0]
        if cmd in (DIAG_EXT_MSG_F, DIAG_EXT_MSG_TERSE_F):
            # ext msg: cmd, ..., then a NUL-separated format string and file name
            text = b"".join(c.to_bytes(1, "little") for c in p if 32 <= c < 127)
            print("F3: %s" % text.decode("ascii", "replace"), flush=True)
        else:
            print("<< cmd=0x%02x len=%d %s" % (cmd, len(p),
                                               binascii.hexlify(p[:48]).decode()),
                  flush=True)

    def nv_read(item):
        """DIAG_NV_READ_F: cmd, item, 128 bytes of payload, status."""
        send(struct.pack("<BH", 0x26, item) + b"\0" * 128 + b"\0\0")
        end = time.monotonic() + 3
        buf = b""
        while time.monotonic() < end:
            try:
                data = os.read(fd, 0x4000)
            except BlockingIOError:
                time.sleep(0.005)
                continue
            buf += data
            pkts, buf = unframe(buf)
            for pk in pkts:
                if pk and pk[0] == 0x26 and len(pk) >= 133:
                    got = struct.unpack_from("<H", pk, 1)[0]
                    status = struct.unpack_from("<H", pk, 131)[0]
                    if got == item:
                        return status, pk[3:131]
        return None, None

    if len(sys.argv) > 3 and sys.argv[3] == "nv":
        for item in (int(x, 0) for x in sys.argv[4].split(",")):
            st, val = nv_read(item)
            if st is None:
                print("NV %d: no answer" % item, flush=True)
            else:
                print("NV %d: status=%d first16=%s" %
                      (item, st, binascii.hexlify(val[:16]).decode()), flush=True)
        os.close(fd)
        return

    if len(sys.argv) > 3 and sys.argv[3] == "ranges":
        # DIAG_EXT_MSG_CONFIG_F op 1: which subsystem id ranges exist
        send(struct.pack("<BBH", DIAG_EXT_MSG_CONFIG_F, 1, 0))
        end = time.monotonic() + 4
        buf = b""
        while time.monotonic() < end:
            try:
                data = os.read(fd, 0x8000)
            except BlockingIOError:
                time.sleep(0.005)
                continue
            buf += data
            pkts, buf = unframe(buf)
            for pk in pkts:
                if pk and pk[0] == DIAG_EXT_MSG_CONFIG_F:
                    print("ranges reply, %d bytes" % len(pk), flush=True)
                    cnt = struct.unpack_from("<I", pk, 4)[0] if len(pk) >= 8 else 0
                    print("range count %d" % cnt, flush=True)
                    # each range is a pair of 16-bit ssids, not 32-bit
                    ranges = []
                    for i in range(cnt):
                        off = 8 + i * 4
                        if off + 4 > len(pk):
                            break
                        a, b = struct.unpack_from("<2H", pk, off)
                        ranges.append((a, b))
                        print("  ssid %5d..%-5d" % (a, b), flush=True)

                    # now set every level bit for every range one range at a
                    # time: SET_ALL_MASKS is acknowledged and then ignored
                    mask = int(sys.argv[2], 0)
                    for a, b in ranges:
                        n = b - a + 1
                        # struct diag_msg_build_mask_t from Xiaomi's diag_masks.h:
                        # cmd, sub_cmd, ssid_first, ssid_last, status, padding,
                        # then one 32-bit runtime mask per ssid in the range
                        # Operation codes from Xiaomi's diagchar.h: 1 get ssid
                        # ranges, 2 get build mask, 3 GET msg mask, 4 SET msg
                        # mask, 5 set all.  Asking 3 to write is why the masks
                        # kept reading back as zero.
                        pkt = struct.pack("<BBHHBB", DIAG_EXT_MSG_CONFIG_F, 4,
                                          a, b, 0, 0) + struct.pack("<%dI" % n, *([mask] * n))
                        send(pkt)
                        time.sleep(0.05)
                    print("masks set for %d ranges" % len(ranges), flush=True)
                    time.sleep(1)
                    send(bytes([0x60, 0x01]))
                    pump(float(sys.argv[1]) if len(sys.argv) > 1 else 20)
                    os.close(fd)
                    return
        print("no ranges answer", flush=True)
        os.close(fd)
        return

    print("--- version request", flush=True)
    send(bytes([DIAG_VERNO_F]))
    pump(3, want=DIAG_VERNO_F)

    print("--- enabling every F3 message", flush=True)
    # cmd, operation, pad, runtime mask.  The modem answers 0x13/0x14 (bad
    # parameter / bad length) to anything wider than this.
    #
    # Level bits: 1 low, 2 medium, 4 high, 8 error, 0x10 fatal.  Asking for all
    # of them floods a 1 KB MHI channel and takes the modem down with it, so the
    # default here is error and fatal only - which is what we are after anyway.
    mask = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x18
    print("runtime mask %#x" % mask, flush=True)
    send(struct.pack("<BBHI", DIAG_EXT_MSG_CONFIG_F, MSG_EXPAND_CONF, 0, mask))
    pump(3)

    print("--- enabling the event stream", flush=True)
    # DIAG_EVENT_REPORT_F: one byte, 1 = start.  Events are far lighter than F3
    # and a peripheral that ignores message masks often still reports these.
    send(bytes([0x60, 0x01]))
    pump(2)

    print("--- listening", flush=True)
    pump(float(sys.argv[1]) if len(sys.argv) > 1 else 20)
    os.close(fd)


if __name__ == "__main__":
    main()
