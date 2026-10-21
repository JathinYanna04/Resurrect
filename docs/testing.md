# Testing: what is tested where

resurrect is developed on a computer and has, so far, been tested in containers, not on a phone. This page says exactly what that covers. It is updated whenever coverage changes. **If you run resurrect on a real device, a device report issue helps a lot.**

## Test layers

| Layer | Runs on | What it proves |
|---|---|---|
| shellcheck | any Linux | no shell scripting mistakes it can detect |
| `tests/bats/` (76 tests; inside Termux one skips by design) | any Linux; also inside Termux | process matching, pidfile rules, locking, config parsing, detection with a fake `getprop`/`/proc`, module contract, profiles, eligibility, checksums, boot script, cron block, CLI and dry-run setup for every profile, backup pull script |
| `tests/python/` (25 tests) | any Python 3.11+; also inside Termux | smart alerts against a mock LLM and ntfy server (RSS/Atom/JSON/web parsing, de-duplication, scoring, watch jobs, failure alerts, cron lines), DNS probe against a fake DNS server, privacy scanner |
| `tests/termux-docker/integration.sh` (43 checks) | official Termux Docker image (x86_64): the real Termux userland, `pkg`, Termux's bash, coreutils and Python | a real non-interactive install and the behaviour below |

```sh
tests/termux-docker/run.sh --install     # everything above, inside Termux
```

## The Termux integration test

The test installs `base, ntfy, vaultwarden, adguard (no root), copyparty, filebrowser, syncthing, backup, monitor, alerts` with `rez --yes setup --config ...`, downloading every pinned release for real and checking its checksum, then verifies:

- **base:** key-only SSH (password login off), sshd reachable, cron block, boot script, `rez` wrapper, secrets folder mode 700.
- **ntfy:** health; resurrect's token can publish but not read; the phone user can read; anonymous access refused.
- **Vaultwarden:** HTTPS (self-signed); sign-ups open after install; `close-signups` makes a real registration attempt fail; the admin token is an argon2id hash; the auto-close cron line disappears.
- **AdGuard Home (no root):** starts with resurrect's pre-written config (the first-run wizard can't run without root); answers DNS on 5335; the generated password logs in; a wrong password and unauthenticated API calls are refused.
- **copyparty:** the password reads a file; anonymous cannot.
- **File Browser:** admin login. **Syncthing:** GUI requires authentication; runs as one process.
- **Backups:** rotation keeps N; the restore test passes; the archive contains the Vaultwarden database; folder mode 700.
- **Monitor:** a killed service is detected, an alert arrives in ntfy, and the service is restarted.
- **Stale pidfile:** a pidfile pointing at an unrelated live process does not stop `rez start`, and that process is left alone.
- **Boot:** with everything stopped, the boot script fired twice at once: the second copy exits on the lock, every service comes back, nothing runs twice; running it again starts nothing new.
- `rez doctor` runs; `rez uninstall --purge` removes a module's data.

Bugs these tests have already caught (all fixed): ntfy needing its server to create the user database first; AdGuard refusing to run its wizard without root; copyparty missing a dependency; Syncthing running two processes; Go programs finding no CA certificates; module install steps whose errors were silently ignored; the backup copy on the computer losing its 700 mode.

## Per module

| Module | Tested | Not tested (needs a real device or account) |
|---|---|---|
| base | Termux container: packages, sshd, cron, boot script and lock | Termux:Boot actually running at boot, wake lock, battery optimization |
| tailscale | dry run only | everything real: proot Debian, userspace tailscaled, login, `tailscale cert` |
| cloudflared | dry run only | everything real (needs a Cloudflare account) |
| ntfy | Termux container (amd64) | arm64 binary on a phone, delivery to the phone app |
| vaultwarden | Termux container (amd64), self-signed HTTPS | Tailscale certificate, arm64 binary, Bitwarden apps |
| adguard | Termux container (amd64), no-root mode | root mode (Magisk `service.d` launcher), port 53 |
| copyparty | Termux container | phone, SD card paths |
| filebrowser | Termux container (amd64) | phone |
| syncthing | Termux container | pairing with another device |
| backup | Termux container; pull script against a fake phone | nightly cron timing on a phone, pulling over a real network |
| monitor | Termux container | battery temperature/charging sensors |
| alerts | mock LLM and ntfy server | your real LLM endpoint and real feeds (`rez alerts test JOB` checks feeds) |
| jellyfin | dry run only | everything real |
| acc | dry run only | everything real (needs root) |

Each module's `MOD_TESTED` line says the same thing (`rez modules` shows modules; the line is in `modules/NAME.sh`).

## What a container cannot show

The Termux image runs on a normal Linux kernel, so these Android behaviours are untested until someone runs resurrect on a phone:

- Termux:Boot, the phantom process killer, Doze and battery optimization killing processes.
- PID reuse after a real reboot (the logic is tested with fake `/proc` trees and a decoy process).
- proot on an Android kernel (tailscaled, Jellyfin), arm64 binaries, SD card permissions.
- `getprop`, `pm`, `settings` and root (`su`, Magisk) on a real system (tested with mocks).

The original single-device setup these scripts generalise did run on a real Android tablet for weeks (Termux, proot tailscaled, AdGuard root mode, Vaultwarden, ntfy, ACC), and its outages are where the reliability rules come from. The generic code paths still need their own device testing.
