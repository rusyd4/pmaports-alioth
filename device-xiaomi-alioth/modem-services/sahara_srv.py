#!/usr/bin/env python3
"""Sahara image server for a flashless SDX55 hanging off SM8250 PCIe2.

The modem's SBL asks for the rest of its boot chain over the SAHARA MHI
channel; mhi_wwan_ctrl exposes that channel as a wwan char device.
"""
import errno, glob, os, struct, sys, time

FWDIR = "/lib/firmware/qcom/sdx55m"

# Numbering follows the QDU100 table in drivers/accel/qaic/sahara.c.  Where
# QDU100 feeds zeros it simply lacks that image, so the slot keeps its real
# meaning here (40 = apdp, 42 = sec).
IMAGE_TABLE = {
    4:  "apps.mbn",
    6:  "apps.mbn",
    8:  "qdsp6sw.mbn",
    12: "qdsp6sw.mbn",
    # Dumps of mdm1m9kefs1..3.  The stock efs*.bin next to the other images are
    # placeholders - signed "IMGEFS- DUMMY-1", 512 bytes, no NV at all - and the
    # modem boots into factory-test mode with no IMEI when fed those.
    16: "efs1_real.bin",
    17: "efs2_real.bin",
    20: "efs3_real.bin",
    23: "aop.mbn",
    25: "tz.mbn",
    26: "zeros_1sector.bin",   # SSD_KEYS in the classic table, we have no such file
    29: "acdb.mbn",            # the modem's own boot log names slot 29 "ACDB"
    33: "hyp.mbn",
    34: "mdmddr.mbn",
    36: "multi_image_qti.mbn",
    37: "multi_image.mbn",
    38: "xbl_cfg.elf",
    39: "apps.mbn",
    40: "apdp.mbn",
    41: "devcfg.mbn",
    42: "sec.elf",
}

CMD = {1: "HELLO", 2: "HELLO_RESP", 3: "READ_DATA", 4: "END_OF_IMAGE",
       5: "DONE", 6: "DONE_RESP", 7: "RESET", 8: "RESET_RESP",
       9: "MEM_DEBUG", 0xa: "MEM_READ", 0xb: "CMD_READY", 0xc: "SWITCH_MODE",
       0xd: "EXECUTE", 0xe: "EXECUTE_RESP", 0xf: "EXECUTE_DATA",
       0x10: "MEM_DEBUG64", 0x11: "MEM_READ64", 0x12: "READ_DATA64",
       0x13: "RESET_STATE", 0x14: "WRITE_DATA"}

WRITE_CHUNK = 0x400    # MHI_WWAN_MAX_MTU. The device's max_length from HELLO
                        # bounds command packets, not raw image data.

MEMDUMP_DIR = "/var/lib/alioth-modem/mdmdump"
MAX_REGION = 4 << 20     # don't try to pull hundreds of MB over a 1 KB channel

PROGRESS_STEP = 1 << 20  # qdsp6sw is 84 MB in 1 KB pieces; log a line per MB so
                         # a stalled run says where it stopped.


def log(*a):
    print("[%.3f]" % time.monotonic(), *a, flush=True)


class Server:
    def __init__(self, path):
        self.path = path
        self.fd = os.open(path, os.O_RDWR)
        self.cache = {}
        self.active = None
        self.sent = 0
        self.next_off = 0
        self.marker = 0
        self.debug_asked = False

    def read_exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = os.read(self.fd, min(0x10000, n - len(buf)))
            if not chunk:
                raise OSError(errno.EIO, "channel closed mid-transfer")
            buf += chunk
        return buf

    def mem_read(self, addr, length, wide):
        if wide:
            self.send(struct.pack("<II2Q", 0x11, 0x18, addr, length))
        else:
            self.send(struct.pack("<4I", 0xa, 0x10, addr, length))
        return self.read_exact(length)

    def memory_debug(self, addr, length, wide):
        log("MEM_DEBUG: table at 0x%x, %d bytes, %d-bit"
            % (addr, length, 64 if wide else 32))
        try:
            table = self.mem_read(addr, length, wide)
        except OSError as e:
            log("!! cannot read the debug table: %s" % e)
            return

        esz = 64 if wide else 52
        entries = []
        for i in range(len(table) // esz):
            e = table[i * esz:(i + 1) * esz]
            if wide:
                t, a, l = struct.unpack_from("<3Q", e, 0)
                desc, fname = e[24:44], e[44:64]
            else:
                t, a, l = struct.unpack_from("<3I", e, 0)
                desc, fname = e[12:32], e[32:52]
            desc = desc.split(b"\0")[0].decode("ascii", "replace")
            fname = fname.split(b"\0")[0].decode("ascii", "replace")
            entries.append((t, a, l, desc, fname))
            log("region %2d  type=%d  addr=0x%08x  len=%-9d  %-20s %s"
                % (i, t, a, l, desc, fname))

        try:
            os.makedirs(MEMDUMP_DIR, exist_ok=True)
        except OSError as e:
            log("!! cannot create %s: %s" % (MEMDUMP_DIR, e))
            return

        for i, (t, a, l, desc, fname) in enumerate(entries):
            if l == 0:
                continue
            take = min(l, MAX_REGION)
            name = fname or ("region%02d.bin" % i)
            name = name.replace("/", "_")
            try:
                data = self.mem_read(a, take, wide)
            except OSError as e:
                log("!! region %d (%s): %s" % (i, name, e))
                return
            with open(os.path.join(MEMDUMP_DIR, name), "wb") as f:
                f.write(data)
            log("saved %s (%d of %d bytes)" % (name, take, l))

    def send(self, data):
        for i in range(0, len(data), WRITE_CHUNK):
            piece = data[i:i + WRITE_CHUNK]
            while True:
                try:
                    os.write(self.fd, piece)
                    break
                except OSError as e:
                    if e.errno in (errno.EAGAIN, errno.ENOMEM, errno.ENOSPC):
                        time.sleep(0.001)
                        continue
                    raise

    def image(self, image_id):
        if image_id in self.cache:
            return self.cache[image_id]
        name = IMAGE_TABLE.get(image_id)
        if not name:
            log("!! unknown image id %d - no file mapped" % image_id)
            return None
        path = os.path.join(FWDIR, name)
        try:
            with open(path, "rb") as f:
                blob = f.read()
        except OSError as e:
            log("!! image %d -> %s: %s" % (image_id, path, e))
            return None
        log("loaded image %d -> %s (%d bytes)" % (image_id, name, len(blob)))
        self.cache[image_id] = blob
        return blob

    def hello_resp(self, mode):
        # cmd, length, version, version_compat, status, mode, 6 reserved = 0x30
        return struct.pack("<12I", 2, 0x30, 2, 1, 0, mode, 0, 0, 0, 0, 0, 0)

    def read_data(self, img, off, ln):
        blob = self.image(img)
        if blob is None:
            return
        if off + ln > len(blob):
            log("!! image %d: request %d+%d beyond %d" % (img, off, ln, len(blob)))
            ln = max(0, len(blob) - off)
        if img != self.active:
            log("READ_DATA image=%d starts (offset=%d len=%d, size=%d)"
                % (img, off, ln, len(blob)))
            self.active = img
            self.next_off = off
            self.marker = 0
        if off != self.next_off:
            log("READ_DATA image=%d jumps: expected offset %d, asked %d"
                % (img, self.next_off, off))
        self.next_off = off + ln
        self.sent += ln
        if self.sent - self.marker >= PROGRESS_STEP:
            self.marker = self.sent
            log("progress image=%d offset=%d sent=%d of %d"
                % (img, off, self.sent, len(blob)))
        self.send(blob[off:off + ln])

    def reopen(self):
        """The SAHARA channel only exists in EE=SBL, so the port disappearing is
        how a normal hand-off looks from here.  Wait for it rather than die."""
        try:
            os.close(self.fd)
        except OSError:
            pass
        self.fd = -1
        self.active = None
        self.sent = 0
        self.next_off = 0
        self.marker = 0
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            try:
                self.fd = os.open(self.path, os.O_RDWR)
                log("channel reopened on %s" % self.path)
                return True
            except OSError:
                time.sleep(0.02)
        log("!! channel never came back, giving up")
        return False

    def gone(self, why):
        log("!! channel gone (%s) during image=%s after %d bytes"
            % (why, self.active, self.sent))
        return self.reopen()

    def run(self):
        while True:
            try:
                pkt = os.read(self.fd, 0x10000)
            except OSError as e:
                if self.gone(errno.errorcode.get(e.errno, str(e.errno))):
                    continue
                return
            if not pkt:
                if self.gone("EOF"):
                    continue
                return
            if len(pkt) < 8:
                log("runt packet %s" % pkt.hex())
                continue
            cmd, length = struct.unpack("<II", pkt[:8])
            if cmd == 1:
                ver, compat, maxlen, mode = struct.unpack("<4I", pkt[8:24])
                log("HELLO ver=%d compat=%d maxlen=%d mode=%d" % (ver, compat, maxlen, mode))
                self.send(self.hello_resp(mode))
            elif cmd == 3:
                img, off, ln = struct.unpack("<3I", pkt[8:20])
                self.read_data(img, off, ln)
            elif cmd == 0x12:
                img, off, ln = struct.unpack("<3Q", pkt[8:32])
                self.read_data(img, off, ln)
            elif cmd == 4:
                img, status = struct.unpack("<2I", pkt[8:16])
                log("END_OF_IMAGE image=%d status=%d (%d bytes sent)" % (img, status, self.sent))
                self.sent = 0
                self.marker = 0
                self.next_off = 0
                self.active = None
                if status == 0:
                    self.send(struct.pack("<2I", 5, 8))     # DONE
                else:
                    log("!! device reported failure on image %d" % img)
            elif cmd == 6:
                st = struct.unpack("<I", pkt[8:12])[0] if len(pkt) >= 12 else -1
                log("DONE_RESP image_tx_status=%d" % st)
                if st == 1:
                    log("ALL IMAGES LOADED! SBL transitioning to AMSS / Mission Mode...")
            elif cmd == 9:
                a, l = struct.unpack("<2I", pkt[8:16])
                self.memory_debug(a, l, False)
            elif cmd == 0x10:
                a, l = struct.unpack("<2Q", pkt[8:24])
                self.memory_debug(a, l, True)
            elif cmd == 0xb:
                log("CMD_READY -> SWITCH_MODE(image tx pending)")
                self.send(struct.pack("<3I", 0xc, 0xc, 0))
            else:
                log("<< %s (0x%x) len=%d %s" %
                    (CMD.get(cmd, "?"), cmd, length, pkt[:48].hex()))


def wait_for_port():
    while True:
        ports = sorted(glob.glob("/dev/wwan*firehose*") + glob.glob("/dev/wwan*sahara*"))
        if ports:
            return ports[0]
        time.sleep(0.05)


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else wait_for_port()
    log("serving Sahara on %s" % path)
    Server(path).run()
