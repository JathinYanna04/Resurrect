#!/usr/bin/env python3
"""Fail if the repository contains personal data or secrets.

Two layers:
  1. Generic patterns that should never be committed to a public project:
     email addresses, real IPv4 addresses, tailnet hostnames, home-directory
     paths, private keys, API tokens.
  2. A personal denylist that lives OUTSIDE the repository (never commit it):
     $REZ_DENYLIST or ~/.config/resurrect-dev/denylist. One case-insensitive
     string per line; "file:PATH" adds every secret-shaped token from PATH
     (10+ characters mixing letters and digits; point it at your secrets so
     their values can never slip in; add short passwords as plain lines).
     Matches are reported by entry number only, never by value.

Usage:
  privacy-scan.py                 scan every tracked and untracked (non-ignored) file
  privacy-scan.py --staged        scan the staged versions (pre-commit hook)
  privacy-scan.py --commits [REV] also scan commit authors and messages
  privacy-scan.py FILE...         scan specific files

A line containing "privacy-scan: allow" is exempt from the generic patterns
(never from the denylist).

Allowlist: $REZ_ALLOWLIST or ~/.config/resurrect-dev/allowlist, also outside
the repository. One exact string per line (case-insensitive) that is removed
before any check, e.g. your own GitHub noreply commit address, which would
otherwise match your denylisted name.
"""
import ipaddress
import os
import re
import subprocess
import sys

ALLOW_MARK = "privacy-scan: allow"

EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
EMAIL_OK = re.compile(
    r"@(example\.(com|org|net)|[a-z0-9.-]*\.invalid|users\.noreply\.github\.com|anthropic\.com)$"
    r"|^git@github\.com$|^noreply@",
    re.I,
)
IPV4 = re.compile(r"(?<![\w.])(\d{1,3}(?:\.\d{1,3}){3})(?![\w.])")
# Public resolvers and well-known addresses that docs legitimately mention.
IPV4_OK = {
    "0.0.0.0", "1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4", "9.9.9.9",
    "149.112.112.112", "100.100.100.100", "255.255.255.255",
}
DOC_NETS = [ipaddress.ip_network(n) for n in (
    "127.0.0.0/8", "192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24",
)]
PATTERNS = [
    ("tailnet hostname", re.compile(r"\btail[0-9a-f]{4,}\.ts\.net\b", re.I)),
    ("home directory path", re.compile(r"/home/(?!user\b|runner\b|you\b|\$)[a-z_][a-z0-9_-]*/|/Users/[A-Za-z]+/")),
    ("private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("Tailscale auth key", re.compile(r"\btskey-[a-z]+-[A-Za-z0-9]{10,}")),
    ("ntfy token", re.compile(r"\btk_[A-Za-z0-9]{29}\b")),
    ("API key", re.compile(r"\b(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16})\b")),
    ("device serial", re.compile(r"serialno\s*[=:]\s*[A-Za-z0-9]{6,}", re.I)),
    ("ssh public key", re.compile(r"\bssh-(ed25519|rsa) AAAA[A-Za-z0-9+/]{40,}")),
]

TEXT_LIMIT = 2_000_000


def ip_ok(s):
    try:
        ip = ipaddress.ip_address(s)
    except ValueError:
        return True  # version numbers like 1.2.3.400
    if s in IPV4_OK:
        return True
    return any(ip in n for n in DOC_NETS)


def looks_secret(tok):
    """Secret-shaped: 10+ chars mixing letters and digits, not a URL or label."""
    return (len(tok) >= 10 and re.search(r"[A-Za-z]", tok) and re.search(r"[0-9]", tok)
            and not re.match(r"^(https?|//|ssh-|ecdsa-)", tok, re.I)
            and not re.fullmatch(r"[0-9./-]+", tok))


def load_allowlist():
    path = os.environ.get("REZ_ALLOWLIST") or os.path.expanduser("~/.config/resurrect-dev/allowlist")
    try:
        with open(path, encoding="utf-8") as fh:
            return [ln.strip().lower() for ln in fh if ln.strip() and not ln.lstrip().startswith("#")]
    except OSError:
        return []


ALLOW = load_allowlist()


def strip_allowed(line):
    if not ALLOW:
        return line
    low = line.lower()
    for a in ALLOW:
        while a in low:
            i = low.index(a)
            line, low = line[:i] + line[i + len(a):], low[:i] + low[i + len(a):]
    return line


def load_denylist():
    path = os.environ.get("REZ_DENYLIST") or os.path.expanduser("~/.config/resurrect-dev/denylist")
    entries = []
    if not os.path.isfile(path):
        return entries, None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("file:"):
                src = os.path.expanduser(line[5:])
                try:
                    with open(src, encoding="utf-8", errors="replace") as sf:
                        for tok in re.split(r"[\s=:\"',;]+", sf.read()):
                            if looks_secret(tok):
                                entries.append(tok.lower())
                except OSError:
                    print(f"warning: denylist source not readable: {src}", file=sys.stderr)
                continue
            entries.append(line.lower())
    return entries, path


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def scan_text(name, text, deny, findings):
    for n, line in enumerate(text.splitlines(), 1):
        line = strip_allowed(line)
        low = line.lower()
        for i, d in enumerate(deny, 1):
            if d in low:
                findings.append(f"{name}:{n}: matches personal denylist entry #{i}")
        if ALLOW_MARK in line:
            continue
        for m in EMAIL.finditer(line):
            if not EMAIL_OK.search(m.group(0)):
                findings.append(f"{name}:{n}: email address {m.group(0)!r}")
        for m in IPV4.finditer(line):
            if not ip_ok(m.group(1)):
                findings.append(f"{name}:{n}: IP address {m.group(1)!r}")
        for label, rx in PATTERNS:
            if rx.search(line):
                findings.append(f"{name}:{n}: {label}")


def main(argv):
    deny, deny_path = load_denylist()
    staged = "--staged" in argv
    commits = "--commits" in argv
    rest = [a for a in argv if not a.startswith("--")]
    findings = []
    self_path = os.path.relpath(__file__)

    if rest and not commits:
        files = [(f, None) for f in rest]
    elif staged:
        files = [(f, ":" + f) for f in git("diff", "--cached", "--name-only", "--diff-filter=ACMR").split("\n") if f]
    else:
        files = [(f, None) for f in git("ls-files", "-co", "--exclude-standard").split("\n") if f]

    for f, blob in files:
        try:
            if blob:
                data = subprocess.run(["git", "show", blob], capture_output=True, check=True).stdout
            else:
                if not os.path.isfile(f):
                    continue
                with open(f, "rb") as fh:
                    data = fh.read(TEXT_LIMIT)
        except (OSError, subprocess.CalledProcessError):
            continue
        if b"\0" in data[:8000]:
            text = data.decode("latin-1")
            for i, d in enumerate(deny, 1):
                if d in text.lower():
                    findings.append(f"{f}: binary file matches personal denylist entry #{i}")
            continue
        text = data.decode("utf-8", errors="replace")
        if os.path.normpath(f) == os.path.normpath(self_path):
            # The scanner holds the patterns themselves: denylist only.
            for n, line in enumerate(text.splitlines(), 1):
                for i, d in enumerate(deny, 1):
                    if d in line.lower():
                        findings.append(f"{f}:{n}: matches personal denylist entry #{i}")
            continue
        scan_text(f, text, deny, findings)

    if commits:
        rev = rest[0] if rest else "HEAD"
        try:
            log = git("log", "--format=%H%n%an <%ae>%n%cn <%ce>%n%B%n--end--", rev)
        except subprocess.CalledProcessError:
            log = ""
        scan_text("commit-log", log, deny, findings)

    if deny_path is None:
        print("note: no personal denylist found (~/.config/resurrect-dev/denylist); generic checks only",
              file=sys.stderr)
    if findings:
        print("privacy scan FAILED:", file=sys.stderr)
        for x in findings:
            print("  " + x, file=sys.stderr)
        return 1
    print(f"privacy scan passed ({len(files)} files, {len(deny)} denylist entries)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
