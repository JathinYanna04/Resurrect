# Testing

This page explains how to run resurrect's tests, how the Termux container runner works, and exactly what has been tested where. It is for contributors and for anyone deciding how far to trust a pre-release. resurrect has so far been tested on Linux and in the official Termux Docker image, not yet on a range of real devices, and this page says precisely what that covers.

## Contents

- [Prerequisites](#prerequisites)
- [Test layers](#test-layers)
- [Run the tests](#run-the-tests)
- [The Termux container runner](#the-termux-container-runner)
- [What the integration test checks](#what-the-integration-test-checks)
- [Tested and untested, by module](#tested-and-untested-by-module)
- [What a container cannot show](#what-a-container-cannot-show)
- [Continuous integration](#continuous-integration)
- [Troubleshooting](#troubleshooting)

## Prerequisites

| Tool | Needed for | Notes |
|---|---|---|
| Bash, `python3` 3.11 or newer, `rsync` | Unit tests | Any Linux distribution |
| [bats-core](https://github.com/bats-core/bats-core) 1.11.1 | Shell unit tests | Not packaged in Termux; install it from the tag below |
| Docker | Termux container tests and shellcheck | The container runs x86_64 |

To install bats-core in your home folder:

```bash
git clone --depth 1 --branch v1.11.1 https://github.com/bats-core/bats-core /tmp/bats-core
/tmp/bats-core/install.sh ~/.local
```

## Test layers

| Layer | Size | Runs on | What it proves |
|---|---|---|---|
| shellcheck | All shell scripts | Any Linux, through Docker | No shell mistakes that shellcheck can detect |
| Privacy scan | All files and commit history | Any Linux | No personal data, addresses or tokens in the repository |
| `tests/bats/` | 77 tests | Linux, and inside Termux | Process matching, pidfile rules, locking, config parsing, device detection with a fake `getprop` and `/proc`, the module contract, profiles, eligibility, checksums, the boot script, the cron block, CLI and dry-run setup for every profile, the backup pull script |
| `tests/python/` | 25 tests | Python 3.11+, and inside Termux | Smart alerts against a mock LLM and ntfy server, the DNS probe against a fake DNS server, the privacy scanner |
| `tests/termux-docker/integration.sh` | 43 checks | The official Termux image (x86_64) | A real non-interactive install and the behaviour listed below |

Inside Termux, one bats test skips by design: it checks that setup refuses to run outside Termux.

## Run the tests

From the repository root:

```bash
bats tests/bats                                   # shell unit tests
python3 -m unittest discover -s tests/python      # Python unit tests
python3 scripts/privacy-scan.py                   # privacy scan of all files
```

shellcheck runs in Docker with the same version and file list as CI:

```bash
docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.10.0 -x \
  bin/rez lib/*.sh modules/*.sh install.sh boot/resurrect-boot.sh scripts/hooks/* \
  extras/laptop/*.sh extras/laptop/dns-fallback/*.sh tests/termux-docker/*.sh tests/mocks/getprop
```

When everything passes, bats ends with `ok 77 ...` and no `not ok` lines, and the Python run ends with:

```text
Ran 25 tests in 1.393s

OK
```

To try a whole setup on a normal Linux machine without changing anything:

```bash
REZ_ALLOW_NON_TERMUX=1 HOME=$(mktemp -d) bin/rez --dry-run --yes setup --profile standard
```

## The Termux container runner

`tests/termux-docker/run.sh` runs the tests inside [termux/termux-docker](https://github.com/termux/termux-docker): the real Termux userland, with `$PREFIX`, `pkg`, and Termux's own Bash, coreutils and Python, but no Android underneath.

```bash
tests/termux-docker/run.sh                  # bats and Python tests inside Termux
tests/termux-docker/run.sh --install        # the same, plus the real install (integration.sh)
tests/termux-docker/run.sh --integration    # only the real install
```

The first run builds a local image called `resurrect-test` from `tests/termux-docker/Dockerfile`, which adds the test tools (bats, `git`, `rsync` and a few others) to the Termux image so later runs don't download them again. Termux mirrors can be slow, so the first build can take a while. Set `REZ_TEST_IMAGE` to use a different image name.

The checkout is mounted read-only and copied inside the container, so tests can never modify your working tree. Every stage runs even if an earlier one fails, and the run ends with a summary:

```text
==> summary
  bats: ok
  python: ok
  integration: ok
```

Rebuild the image after changing the Dockerfile:

```bash
docker build -t resurrect-test tests/termux-docker
```

## What the integration test checks

The test installs `base`, `ntfy`, `vaultwarden`, `adguard` (no root), `copyparty`, `filebrowser`, `syncthing`, `backup`, `monitor` and `alerts` with `rez --yes setup --config ...`. It downloads every pinned release for real, verifies the checksums, and then checks:

| Area | Checks |
|---|---|
| `base` | Key-only SSH (password login off), sshd reachable, cron block, boot script, `rez` wrapper, secrets folder mode 700 |
| `ntfy` | Health; resurrect's token can publish but not read; the `phone` user can read; anonymous access refused |
| `vaultwarden` | HTTPS (self-signed); sign-ups open after install; `close-signups` makes a real registration attempt fail; the admin token is an argon2id hash; the auto-close cron line disappears |
| `adguard` (no root) | Starts with resurrect's own config; answers DNS on 5335; the generated password logs in; a wrong password and unauthenticated API calls are refused |
| `copyparty` | The password can read a file; anonymous access can't |
| `filebrowser`, `syncthing` | Admin login works; Syncthing's GUI requires authentication and runs as one process |
| `backup` | Rotation keeps N archives; the restore test passes; the archive contains the Vaultwarden database; folder mode 700 |
| `monitor` | A killed service is detected, an alert arrives in ntfy, and the service is restarted |
| Stale pidfile | A pidfile pointing at an unrelated live process doesn't stop `rez start`, and that process is left alone |
| Boot | With everything stopped, the boot script fired twice at once: the second copy exits on the lock, every service comes back, nothing runs twice; running it again starts nothing new |
| Other | `rez doctor` runs; `rez uninstall --purge` removes a module's data |

Bugs these tests caught, all fixed: ntfy needing its server to create the user database first; AdGuard Home refusing to run its wizard without root; copyparty missing a dependency; Syncthing running two processes; Go programs finding no CA certificates; module install errors being silently ignored; the backup copy on the computer losing its 700 mode. One more was found while checking the documentation against the code: the test image pre-installed `argon2`, which hid that a real install never installed it, so the Vaultwarden admin token would have been stored in plain text. The module now installs `argon2`, and the image no longer includes it.

## Tested and untested, by module

| Module | Tested | Not tested yet (needs a real device, an account or root) |
|---|---|---|
| `base` | Termux container: packages, sshd, cron, boot script and lock | Termux:Boot running at boot, wake lock, battery optimization |
| `tailscale` | Dry run only | Everything real: proot Debian, userspace `tailscaled`, login, `tailscale cert` |
| `cloudflared` | Dry run only | Everything real (needs a Cloudflare account) |
| `ntfy` | Termux container (amd64) | arm64 binary on a device, delivery to the ntfy app |
| `vaultwarden` | Termux container (amd64), self-signed HTTPS | Tailscale certificate, arm64 binary, Bitwarden apps |
| `adguard` | Termux container (amd64), no-root mode | Root mode (Magisk `service.d` launcher), port 53 |
| `copyparty` | Termux container | A device, SD card paths |
| `filebrowser` | Termux container (amd64) | A device |
| `syncthing` | Termux container | Pairing with another device |
| `backup` | Termux container; pull script against a fake device | Nightly cron timing on a device, pulling over a real network |
| `monitor` | Termux container | Battery temperature and charging sensors |
| `alerts` | Mock LLM and ntfy server | Your LLM endpoint and real feeds (`rez alerts test JOB` checks feeds) |
| `jellyfin` | Dry run only | Everything real |
| `acc` | Dry run only | Everything real (needs root) |

Each module's `MOD_TESTED` line in `modules/<name>.sh` says the same. Real devices that have been reported are listed in [tested-devices.md](tested-devices.md).

## What a container cannot show

The Termux image runs on a normal Linux kernel, so these Android behaviours stay untested until resurrect runs on real devices:

- Termux:Boot, the phantom process killer, Doze and battery optimization stopping processes.
- PID reuse after a real reboot. The logic is tested with fake `/proc` trees and a decoy process.
- proot on an Android kernel (`tailscaled`, Jellyfin), arm64 binaries, SD card permissions.
- `getprop`, `pm`, `settings` and root (`su`, Magisk) on a real system. They are tested with mocks.

The single-device setup that resurrect generalizes did run on a real Android tablet for weeks, with Termux, proot `tailscaled`, AdGuard Home in root mode, Vaultwarden, ntfy and ACC. Its outages are where the reliability rules come from. The generic code still needs its own device testing.

**If you run resurrect on a device, please send a [device report](https://github.com/JathinYanna04/resurrect/issues/new?template=device-report.yml).**

## Continuous integration

Every push and pull request runs three jobs in GitHub Actions (`.github/workflows/ci.yml`):

| Job | What it runs |
|---|---|
| `shellcheck + privacy scan` | shellcheck v0.10.0, then the privacy scan over all files and the full commit history |
| `unit tests (Linux)` | bats and Python tests on Ubuntu |
| `tests + real install in Termux` | `tests/termux-docker/run.sh --install` |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `bats: command not found` | bats-core is not installed | Install it as shown in [Prerequisites](#prerequisites) and make sure `~/.local/bin` is on your `PATH` |
| The image build fails or hangs on `pkg update` | A slow or broken Termux mirror | Run the build again later |
| A bats test hangs | A background process kept a file descriptor open | Tests run with `BATS_TEST_TIMEOUT=90` in CI; set it locally too |
| `rsync not installed` skips | The pull-script tests need `rsync` | Install `rsync` |
| `setup refuses to run outside Termux` is skipped | You are inside Termux | Expected |
