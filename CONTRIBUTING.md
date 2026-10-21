# Contributing

Thanks for helping. The most useful contributions, in order:

1. **Device reports**: run resurrect on a phone and open a "Device report" issue with `rez device --report`. Every report tells someone else whether their old phone will work.
2. **Bug reports** with `rez doctor` output and log lines.
3. **Fixes and modules.**

## Ground rules

- **Everything must work without root.** Root may only add optional extras (`MOD_ROOT=optional|required`).
- **Never automate flashing, bootloader unlocking or reboots.** Explain and link to official guides instead.
- **No personal data in the repository**: no names, emails, IPs, tailnet names, device serials, secrets or paths from your machine. Use documentation addresses (`192.0.2.x`, `example.com`) in docs and tests.
- **Every download is pinned** with a checksum (`lib/versions.sh`).
- Follow the reliability rules in [docs/writing-a-module.md](docs/writing-a-module.md): `svc_*` helpers (never pidfiles alone), start only if not running, MemAvailable, secrets in files.
- Be honest about testing: update `MOD_TESTED` and [docs/testing.md](docs/testing.md).

## Development setup

```sh
git clone https://github.com/OWNER/resurrect && cd resurrect
git config core.hooksPath scripts/hooks      # privacy scan on commit and push
```

Optional, strongly recommended: a **personal denylist** that the privacy scan checks on every commit. It lives outside the repository and is never committed:

```sh
mkdir -p ~/.config/resurrect-dev
cat > ~/.config/resurrect-dev/denylist <<'EOF'
# one case-insensitive string per line: your name, usernames, hostnames,
# your tailnet name, your IP addresses...
yourname
file:~/path/to/a/secrets-file     # every secret-shaped token in that file
EOF
chmod 600 ~/.config/resurrect-dev/denylist
```

If your GitHub noreply commit address contains a denylisted name, add the exact address to `~/.config/resurrect-dev/allowlist` (also local-only).

## Tests

```sh
bats tests/bats                                  # unit tests, any Linux with bash, python3, rsync
python3 -m unittest discover -s tests/python     # smart alerts, DNS probe, privacy scan
tests/termux-docker/run.sh                       # the same inside the official Termux image
tests/termux-docker/run.sh --install             # + a real install of the container-safe modules
docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.10.0 -x bin/rez lib/*.sh modules/*.sh
python3 scripts/privacy-scan.py
```

Dry-run anything on a normal Linux machine:

```sh
REZ_ALLOW_NON_TERMUX=1 HOME=$(mktemp -d) bin/rez --dry-run --yes setup --profile standard
```

## Style

- Bash, `set -Eeuo pipefail` in entry points, shellcheck-clean.
- Comments explain *why* (often: which outage taught us this), not what.
- Messages to users are short and say what to do next.
- Python is standard library only, 3.11+.

## Commits and pull requests

One logical change per commit, with a message that explains why. The PR template has the checklist.
