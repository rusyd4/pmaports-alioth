#!/usr/bin/env python3
"""Remote file system server for the flashless SDX55.

On entering mission mode the modem opens the EFS MHI channel (stock DT calls it
mhi_chan@10/11) and sends a Sahara HELLO.  It has no storage of its own: its NV -
calibration, IMEI, SIM settings - lives in the phone's mdm1m9kefs1..3 partitions,
and this is how it reads and writes it.  Without an answer it gives up after
about a dozen seconds and drops the PCIe link.

The protocol is Sahara again, but the other way round from sahara_srv.py: there
the modem pulled boot images, here it pulls and pushes its own filesystem.  What
it actually asks for is not documented anywhere we have, so anything unexpected
is logged as hex rather than guessed at.
"""
import errno, glob, os, struct, sys, time

# Dumps of mdm1m9kefs1..3 taken with dd.  Deliberately files, not the block
# devices: until the write side is understood, nothing should reach the flash.
FWDIR = "/lib/firmware/qcom/sdx55m"
IMAGE_TABLE = {
    16: "efs1_real.bin",
    17: "efs2_real.bin",
    20: "efs3_real.bin",
}

CMD = {1: "HELLO", 2: "HELLO_RESP", 3: "READ_DATA", 4: "END_OF_IMAGE",
       5: "DONE", 6: "DONE_RESP", 7: "RESET", 8: "RESET_RESP",
       9: "MEM_DEBUG", 0xa: "MEM_READ", 0xb: "CMD_READY", 0xc: "SWITCH_MODE",
       0xd: "EXECUTE", 0xe: "EXECUTE_RESP", 0xf: "EXECUTE_DATA",
       0x10: "MEM_DEBUG64", 0x11: "MEM_READ64", 0x12: "READ_DATA64",
       0x13: "RESET_STATE", 0x14: "WRITE_DATA"}

WRITE_CHUNK = 0x400          # MHI_WWAN_MAX_MTU
WRITEBACK_DIR = "/var/lib/alioth-modem/efs_writeback"
MAX_REGION = 16 << 20    # the modem has 256 MB of DDR; this is a sanity cap


def log(*a):
    line = "[%.3f] " % time.monotonic() + " ".join(str(x) for x in a)
    print(line, flush=True)
    try:
        with open("/dev/kmsg", "w") as k:
            k.write("EFSSRV: %s\n" % line)
    except OSError:
        pass


class Server:
    def __init__(self, path):
        self.path = path
        self.fd = os.open(path, os.O_RDWR)
        self.cache = {}
        self.written = {}

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
        """The modem answers HELLO_RESP with a region table rather than asking
        for files.  Each entry carries an address, a length and a name - this is
        how it hands its EFS over.  Pull everything and keep it."""
        log("MEM_DEBUG: table at 0x%x, %d bytes, %d-bit"
            % (addr, length, 64 if wide else 32))
        try:
            table = self.mem_read(addr, length, wide)
        except OSError as e:
            log("!! cannot read the region table: %s" % e)
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
            log("region %2d type=%d addr=0x%08x len=%-9d %-20s %s"
                % (i, t, a, l, desc, fname))

        os.makedirs(WRITEBACK_DIR, exist_ok=True)
        for i, (t, a, l, desc, fname) in enumerate(entries):
            if l == 0:
                continue
            take = min(l, MAX_REGION)
            name = (fname or ("region%02d.bin" % i)).replace("/", "_")
            try:
                data = self.mem_read(a, take, wide)
            except OSError as e:
                log("!! region %d (%s): %s" % (i, name, e))
                return
            with open(os.path.join(WRITEBACK_DIR, name), "wb") as f:
                f.write(data)
            log("saved %s (%d of %d bytes)" % (name, take, l))

        # Closing the session is the host's job: the modem waits for it before
        # carrying on, and an unfinished sync is what it gives up on.
        log("regions done, closing the session with RESET")
        self.send(struct.pack("<2I", 7, 8))

    def image(self, image_id):
        if image_id in self.cache:
            return self.cache[image_id]
        name = IMAGE_TABLE.get(image_id)
        if not name:
            log("!! unknown efs image id %d - nothing mapped" % image_id)
            return None
        path = os.path.join(FWDIR, name)
        try:
            with open(path, "rb") as f:
                blob = f.read()
        except OSError as e:
            log("!! image %d -> %s: %s" % (image_id, path, e))
            return None
        log("loaded efs image %d -> %s (%d bytes)" % (image_id, name, len(blob)))
        self.cache[image_id] = blob
        return blob

    def read_data(self, img, off, ln):
        blob = self.image(img)
        if blob is None:
            return
        if off + ln > len(blob):
            log("!! image %d: asked %d+%d, have %d" % (img, off, ln, len(blob)))
            ln = max(0, len(blob) - off)
        log("READ_DATA image=%d off=%d len=%d" % (img, off, ln))
        self.send(blob[off:off + ln])

    def write_data(self, img, off, ln):
        """The modem hands its own NV back.  Keep it in a file next to the dumps
        so a later run can replay it; the flash stays untouched for now."""
        data = b""
        while len(data) < ln:
            chunk = os.read(self.fd, min(0x10000, ln - len(data)))
            if not chunk:
                log("!! channel closed mid WRITE_DATA")
                return
            data += chunk
        os.makedirs(WRITEBACK_DIR, exist_ok=True)
        name = IMAGE_TABLE.get(img, "image%d.bin" % img)
        path = os.path.join(WRITEBACK_DIR, name)
        with open(path, "r+b" if os.path.exists(path) else "wb") as f:
            f.seek(off)
            f.write(data)
        self.written[img] = self.written.get(img, 0) + len(data)
        log("WRITE_DATA image=%d off=%d len=%d (total %d) -> %s"
            % (img, off, ln, self.written[img], path))

    def run(self):
        while True:
            try:
                pkt = os.read(self.fd, 0x10000)
            except OSError as e:
                log("!! channel error: %s" % e)
                return
            if not pkt:
                log("!! channel closed")
                return
            if len(pkt) < 8:
                log("runt packet %s" % pkt.hex())
                continue
            cmd, length = struct.unpack("<II", pkt[:8])

            if cmd == 1:
                ver, compat, maxlen, mode = struct.unpack("<4I", pkt[8:24])
                log("HELLO ver=%d compat=%d maxlen=%d mode=%d" % (ver, compat, maxlen, mode))
                # cmd, length, version, compat, status, mode, 6 reserved
                self.send(struct.pack("<12I", 2, 0x30, ver, compat, 0, mode,
                                      0, 0, 0, 0, 0, 0))
            elif cmd == 3:
                img, off, ln = struct.unpack("<3I", pkt[8:20])
                self.read_data(img, off, ln)
            elif cmd == 0x12:
                img, off, ln = struct.unpack("<3Q", pkt[8:32])
                self.read_data(img, off, ln)
            elif cmd == 0x14:
                img, off, ln = struct.unpack("<3I", pkt[8:20])
                self.write_data(img, off, ln)
            elif cmd == 4:
                img, status = struct.unpack("<2I", pkt[8:16])
                log("END_OF_IMAGE image=%d status=%d" % (img, status))
                if status == 0:
                    self.send(struct.pack("<2I", 5, 8))          # DONE
            elif cmd == 6:
                st = struct.unpack("<I", pkt[8:12])[0] if len(pkt) >= 12 else -1
                log("DONE_RESP status=%d" % st)
            elif cmd == 9:
                a, l = struct.unpack("<2I", pkt[8:16])
                self.memory_debug(a, l, False)
            elif cmd == 0x10:
                a, l = struct.unpack("<2Q", pkt[8:24])
                self.memory_debug(a, l, True)
            elif cmd == 8:
                log("RESET_RESP: session closed")
            elif cmd == 0xb:
                log("CMD_READY -> SWITCH_MODE(image tx pending)")
                self.send(struct.pack("<3I", 0xc, 0xc, 0))
            else:
                log("<< %s (0x%x) len=%d %s"
                    % (CMD.get(cmd, "?"), cmd, length, pkt[:64].hex()))


def wait_for_port(timeout=180):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ports = sorted(glob.glob("/dev/wwan*xmmrpc*"))
        if ports:
            return ports[0]
        time.sleep(0.02)
    return None


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else wait_for_port()
    if not path:
        log("!! EFS port never appeared")
        sys.exit(1)
    log("serving EFS on %s" % path)
    Server(path).run()
