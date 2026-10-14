#!/usr/bin/env python3
"""Bring up a packet data session and keep it up.

qmicli cannot do this on a QRTR device: the WDS client lives in the process that
opened it, so binding the data port in one invocation and starting the session in
the next loses the client ("Unknown client 1 for service wds").  Both steps have
to happen on one socket, and that socket has to stay open for as long as the
session should live.
"""
import ctypes, struct, subprocess, sys, time

WDS_SERVICE = 1
WDS_START_NETWORK = 0x0020
WDS_GET_CURRENT_SETTINGS = 0x002D
WDS_BIND_MUX_DATA_PORT = 0x00A2

# The modem wants 'embedded' here, not 'pcie': from its side the data
# endpoint is its own internal path.  With pcie every bind answers
# Internal(3) no matter what interface number or mux id you pass.
EP_TYPE_EMBEDDED = 3

libqrtr = ctypes.CDLL("libqrtr.so.1")


def find_service(service):
    out = subprocess.run(["qrtr-lookup"], capture_output=True, text=True, timeout=15).stdout
    for line in out.splitlines():
        f = line.split()
        if len(f) >= 5 and f[0].isdigit() and int(f[0]) == service:
            return int(f[3]), int(f[4])
    return None, None


class Qmi:
    def __init__(self, node, port):
        self.sock = libqrtr.qrtr_open(0)
        if self.sock < 0:
            raise RuntimeError("cannot open qrtr socket")
        self.node, self.port = node, port
        self.txn = 0

    def call(self, msg_id, tlvs, timeout=90):
        self.txn = (self.txn + 1) & 0xFFFF
        body = b"".join(struct.pack("<BH", t, len(v)) + v for t, v in tlvs)
        req = struct.pack("<BHHH", 0, self.txn, msg_id, len(body)) + body
        libqrtr.qrtr_sendto(self.sock, self.node, self.port, req, len(req))

        buf = ctypes.create_string_buffer(8192)
        n_node, n_port = ctypes.c_uint32(), ctypes.c_uint32()
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if libqrtr.qrtr_poll(self.sock, 1000) <= 0:
                continue
            n = libqrtr.qrtr_recvfrom(self.sock, buf, 8192,
                                      ctypes.byref(n_node), ctypes.byref(n_port))
            if n <= 0:
                continue
            resp = buf.raw[:n]
            typ, txn, mid, ln = struct.unpack_from("<BHHH", resp, 0)
            if typ == 2 and mid == msg_id:
                return self.parse(resp)
        return None

    @staticmethod
    def parse(resp):
        out, off = {}, 7
        while off + 3 <= len(resp):
            t, ln = struct.unpack_from("<BH", resp, off)
            out[t] = resp[off + 3:off + 3 + ln]
            off += 3 + ln
        return out


def result_of(t):
    if 0x02 in t and len(t[0x02]) >= 4:
        return struct.unpack("<HH", t[0x02][:4])
    return (-1, -1)


def ipv4(n):
    return "%d.%d.%d.%d" % ((n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255)


def main():
    apn = sys.argv[1] if len(sys.argv) > 1 else "internet.mts.ru"
    user = sys.argv[2] if len(sys.argv) > 2 else "mts"
    pw = sys.argv[3] if len(sys.argv) > 3 else "mts"
    iface_no = int(sys.argv[4]) if len(sys.argv) > 4 else 4
    mux_id = int(sys.argv[5]) if len(sys.argv) > 5 else 0
    ep_type = int(sys.argv[6]) if len(sys.argv) > 6 else EP_TYPE_EMBEDDED

    node, port = find_service(WDS_SERVICE)
    if node is None:
        print("WDS service not found")
        return 1
    print("WDS at node %d port %d" % (node, port), flush=True)
    q = Qmi(node, port)

    t = q.call(WDS_BIND_MUX_DATA_PORT, [
        (0x10, struct.pack("<II", ep_type, iface_no)),
        (0x11, bytes([mux_id])),
    ])
    print("bind: %r" % (result_of(t) if t else "no answer",), flush=True)

    tlvs = [(0x14, apn.encode())]
    if user != "-":
        tlvs += [(0x17, user.encode()), (0x18, pw.encode()),
                 (0x19, bytes([3]))]    # auth: PAP or CHAP
    tlvs.append((0x2D, bytes([4])))     # IPv4
    t = q.call(WDS_START_NETWORK, tlvs)
    if not t:
        print("start network: no answer")
        return 1
    res, err = result_of(t)
    if res != 0:
        # TLV 0x10 carries the call end reason when it fails
        print("start network failed: result=%d error=%d extra=%s"
              % (res, err, {k: v.hex() for k, v in t.items()}))
        return 1
    handle = struct.unpack("<I", t[0x01][:4])[0] if 0x01 in t else 0
    print("session up, handle 0x%08x" % handle, flush=True)

    t = q.call(WDS_GET_CURRENT_SETTINGS, [(0x10, struct.pack("<I", 0xFFFFFFFF))])
    if t:
        conf = {}
        if 0x1E in t:
            conf["ip"] = ipv4(struct.unpack("<I", t[0x1E][:4])[0])
        if 0x20 in t:
            conf["gw"] = ipv4(struct.unpack("<I", t[0x20][:4])[0])
        if 0x21 in t:
            conf["mask"] = ipv4(struct.unpack("<I", t[0x21][:4])[0])
        if 0x15 in t:
            conf["dns1"] = ipv4(struct.unpack("<I", t[0x15][:4])[0])
        if 0x16 in t:
            conf["dns2"] = ipv4(struct.unpack("<I", t[0x16][:4])[0])
        if 0x29 in t:
            conf["mtu"] = struct.unpack("<I", t[0x29][:4])[0]
        print("SETTINGS %s" % conf, flush=True)

    print("holding the session open, ctrl-c or kill to drop it", flush=True)
    while True:
        time.sleep(10)


if __name__ == "__main__":
    sys.exit(main())
