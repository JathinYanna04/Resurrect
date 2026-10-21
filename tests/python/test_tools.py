"""dnsprobe.py and privacy-scan.py."""
import importlib.util
import os
import socket
import socketserver
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, REPO / path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


dnsprobe = load("dnsprobe", "lib/dnsprobe.py")


class FakeDNS(socketserver.BaseRequestHandler):
    """TCP DNS server that answers every query with the configured rcode."""
    rcode = 0

    def handle(self):
        n = struct.unpack(">H", self.request.recv(2))[0]
        q = self.request.recv(n)
        resp = q[:2] + struct.pack(">H", 0x8180 | FakeDNS.rcode) + q[4:]
        self.request.sendall(struct.pack(">H", len(resp)) + resp)


class DnsProbeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), FakeDNS)
        cls.port = cls.srv.server_address[1]
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def test_answer_and_nxdomain_are_healthy(self):
        for rc in (0, 3):
            FakeDNS.rcode = rc
            self.assertEqual(dnsprobe.main(["127.0.0.1", str(self.port), "example.com"]), 0)

    def test_servfail_and_refused_are_unhealthy(self):
        for rc in (2, 5):
            FakeDNS.rcode = rc
            self.assertEqual(dnsprobe.main(["127.0.0.1", str(self.port)]), 1)

    def test_closed_port(self):
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
        s.close()
        self.assertEqual(dnsprobe.main(["127.0.0.1", str(port)]), 1)


class PrivacyScanTest(unittest.TestCase):
    def scan(self, content, deny=None, allow=None):
        with tempfile.TemporaryDirectory() as t:
            f = Path(t, "sample.txt")
            f.write_text(content)
            env = dict(os.environ)
            env["REZ_DENYLIST"] = str(Path(t, "deny"))
            env["REZ_ALLOWLIST"] = str(Path(t, "allow"))
            Path(t, "deny").write_text(deny or "")
            Path(t, "allow").write_text(allow or "")
            r = subprocess.run([sys.executable, str(REPO / "scripts/privacy-scan.py"), str(f)],
                               capture_output=True, text=True, env=env)
            return r.returncode, r.stderr

    def test_clean_text_passes(self):
        rc, _ = self.scan("listen 127.0.0.1:2586, docs use 192.0.2.10 and user@example.com\n")
        self.assertEqual(rc, 0)

    def test_systemd_template_units_are_not_emails(self):
        rc, _ = self.scan("systemctl --user enable --now resurrect-pull-backups@phone.timer\n")
        self.assertEqual(rc, 0)

    def test_generic_patterns_fail(self):
        for bad in ("mail me at someone@gmail.com", "server 100.101.102.103",  # privacy-scan: allow
                    "host phone.tail1a2b3c.ts.net", "cd /home/alice/projects",  # privacy-scan: allow
                    "-----BEGIN OPENSSH PRIVATE KEY-----"):  # privacy-scan: allow
            rc, err = self.scan(bad + "\n")
            self.assertEqual(rc, 1, bad)

    def test_allow_marker_skips_generic_but_not_denylist(self):
        rc, _ = self.scan("someone@gmail.com  # privacy-scan: allow\n")  # privacy-scan: allow
        self.assertEqual(rc, 0)
        rc, err = self.scan("secretname  # privacy-scan: allow\n", deny="secretname\n")
        self.assertEqual(rc, 1)
        self.assertNotIn("secretname", err.split("entry")[0].split(":")[-1])

    def test_denylist_is_case_insensitive_and_never_echoed(self):
        rc, err = self.scan("Hello MyName here\n", deny="myname\n")
        self.assertEqual(rc, 1)
        self.assertIn("denylist entry #1", err)
        self.assertNotIn("myname", err.lower().replace("sample", ""))

    def test_file_entries_take_secret_shaped_tokens(self):
        with tempfile.TemporaryDirectory() as t:
            sec = Path(t, "secret.txt")
            sec.write_text("password: Xk29dLq83mZp\nurl: https://example.com\n")
            rc, _ = self.scan("token Xk29dLq83mZp leaked\n", deny=f"file:{sec}\n")
            self.assertEqual(rc, 1)
            rc, _ = self.scan("the word password is fine\n", deny=f"file:{sec}\n")
            self.assertEqual(rc, 0)

    def test_allowlist_removes_exact_string_only(self):
        addr = "123+someuser@users.noreply.github.com"
        rc, _ = self.scan(f"Author: x <{addr}>\n", deny="someuser\n", allow=addr + "\n")
        self.assertEqual(rc, 0)
        rc, _ = self.scan("someuser wrote this\n", deny="someuser\n", allow=addr + "\n")
        self.assertEqual(rc, 1)


if __name__ == "__main__":
    unittest.main()
