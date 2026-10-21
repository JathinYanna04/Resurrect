#!/usr/bin/env python3
"""dnsprobe.py HOST PORT [NAME] [--udp]: send one DNS A query, exit 0 if the
server answered (any rcode except SERVFAIL/REFUSED). TCP by default: UDP into
userspace tailscaled has crashed it, and TCP also works through it.
Stdlib only, so it runs anywhere Python does."""
import random
import socket
import struct
import sys


def build_query(name):
    qid = random.randint(0, 0xFFFF)
    header = struct.pack(">HHHHHH", qid, 0x0100, 1, 0, 0, 0)
    q = b"".join(bytes([len(p)]) + p.encode() for p in name.rstrip(".").split(".")) + b"\0"
    return qid, header + q + struct.pack(">HH", 1, 1)


def probe(host, port, name, udp=False, timeout=4.0):
    qid, msg = build_query(name)
    if udp:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.settimeout(timeout)
            s.sendto(msg, (host, port))
            data, _ = s.recvfrom(4096)
    else:
        with socket.create_connection((host, port), timeout=timeout) as s:
            s.sendall(struct.pack(">H", len(msg)) + msg)
            raw = b""
            while len(raw) < 2:
                chunk = s.recv(2 - len(raw))
                if not chunk:
                    raise OSError("connection closed")
                raw += chunk
            (n,) = struct.unpack(">H", raw)
            data = b""
            while len(data) < n:
                chunk = s.recv(n - len(data))
                if not chunk:
                    raise OSError("connection closed")
                data += chunk
    rid, flags = struct.unpack(">HH", data[:4])
    if rid != qid:
        raise OSError("mismatched reply id")
    return flags & 0x000F


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    host, port = args[0], int(args[1])
    name = args[2] if len(args) > 2 else f"probe-{random.randint(0, 10**9)}.example.com"
    try:
        rcode = probe(host, port, name, udp="--udp" in argv)
    except (OSError, socket.timeout) as e:
        print(f"no answer: {e}", file=sys.stderr)
        return 1
    if rcode in (2, 5):  # SERVFAIL, REFUSED
        print(f"bad rcode {rcode}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
