# Contributing to resurrect

Thank you for helping. This guide explains how to set up a development checkout, run the tests, keep personal data out of the repository, and send changes. It also explains how to send a device report, which is the most useful contribution of all right now and needs no coding.

By taking part, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Contents

- [Ways to contribute](#ways-to-contribute)
- [Ground rules](#ground-rules)
- [Development setup](#development-setup)
- [Running tests](#running-tests)
- [The privacy scan](#the-privacy-scan)
- [Code style](#code-style)
- [Commits](#commits)
- [Pull requests](#pull-requests)
- [Submitting a device report](#submitting-a-device-report)
- [Troubleshooting](#troubleshooting)

## Ways to contribute

| Contribution | Why it matters |
|---|---|
| [Device reports](#submitting-a-device-report) | resurrect has only been tested in containers. Every report tells someone else whether their old device will work |
| [Bug reports](https://github.com/JathinYanna04/resurrect/issues/new?template=bug.yml) | Include `rez doctor` output and log lines, with passwords, tokens and addresses removed |
| Fixes and new modules | See [docs/writing-a-module.md](docs/writing-a-module.md) |
| Documentation | Corrections are welcome. Every command, flag, port and path must match the code |

Security problems go through a private advisory, not an issue. See [SECURITY.md](SECURITY.md).

## Ground rules

These are not negotiable, because they are what makes resurrect safe to run:

- **Everything must work without root.** Root may only add optional features (`MOD_ROOT=optional` or `required`).
- **Never automate flashing, bootloader unlocking or reboots.** Explain the options and link to official guides instead.
- **No personal data in the repository**: no names, email addresses, IP addresses, tailnet names, device serials, secrets or paths from your machine. Use documentation addresses (`192.0.2.x`, `example.com`) in docs and tests.
- **Every download is pinned** to a version with a checksum in `lib/versions.sh`.
- **Follow the reliability rules** in [docs/writing-a-module.md](docs/writing-a-module.md#reliability-rules): the `svc_*` helpers instead of pidfiles, start only if not running, MemAvailable instead of `free`, secrets in files.
- **Be honest about testing.** Update `MOD_TESTED` and [docs/testing.md](docs/testing.md) whenever coverage changes.

## Development setup

### Prerequisites

- Linux with Bash, `git`, `python3` 3.11 or newer and `rsync`.
- [bats-core](https://github.com/bats-core/bats-core) 1.11.1 and Docker for the full test suite (see [docs/testing.md](docs/testing.md#prerequisites)).

### Steps

1. Clone the repository and enable the hooks, which run the privacy scan on every commit and push:

   ```bash
   git clone https://github.com/JathinYanna04/resurrect
   cd resurrect
   git config core.hooksPath scripts/hooks
   ```

2. Create a personal denylist (strongly recommended). It lives outside the repository and is never committed. The privacy scan checks every commit against it:

   ```bash
   mkdir -p ~/.config/resurrect-dev
   cat > ~/.config/resurrect-dev/denylist <<'EOF'
   # One case-insensitive string per line: your name, usernames, hostnames,
   # your tailnet name, your IP addresses.
   yourname
   # Every secret-shaped token in this file is checked too:
   file:~/path/to/a/secrets-file
   EOF
   chmod 600 ~/.config/resurrect-dev/denylist
   ```

3. If a string you need to commit contains a denylisted word, such as your GitHub noreply address, add that exact string to `~/.config/resurrect-dev/allowlist`, which is also local only.

4. Try a full setup without changing anything:

   ```bash
   REZ_ALLOW_NON_TERMUX=1 HOME=$(mktemp -d) bin/rez --dry-run --yes setup --profile standard
   ```

## Running tests

```bash
bats tests/bats                                  # shell unit tests
python3 -m unittest discover -s tests/python     # smart alerts, DNS probe, privacy scan
tests/termux-docker/run.sh                       # the same, inside the official Termux image
tests/termux-docker/run.sh --install             # plus a real install of the container-safe modules
python3 scripts/privacy-scan.py                  # privacy scan of all files
```

shellcheck runs in Docker with the same version as CI:

```bash
docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.10.0 -x \
  bin/rez lib/*.sh modules/*.sh install.sh boot/resurrect-boot.sh scripts/hooks/* \
  extras/laptop/*.sh extras/laptop/dns-fallback/*.sh tests/termux-docker/*.sh tests/mocks/getprop
```

[docs/testing.md](docs/testing.md) explains each layer and what is tested where.

## The privacy scan

`scripts/privacy-scan.py` fails if the repository contains personal data or secrets. It checks:

- **Generic patterns:** email addresses, real IPv4 addresses, tailnet hostnames, home-directory paths, private keys and API tokens.
- **Your personal denylist**, if you created one. Matches are reported by entry number only, never by value.

| Hook | When | What it scans |
|---|---|---|
| `pre-commit` | Every commit | The staged files |
| `commit-msg` | Every commit | The commit message and the author and committer identity |
| `pre-push` | Every push | All files and the full commit history |

CI runs the same scan on every push. To run it by hand:

```bash
python3 scripts/privacy-scan.py                 # every tracked and untracked file
python3 scripts/privacy-scan.py --staged        # what you are about to commit
python3 scripts/privacy-scan.py --commits       # commit authors and messages too
```

A line containing `privacy-scan: allow` is exempt from the generic patterns, but never from your denylist. Use it only for deliberate test data, such as a fake serial number in a mock.

## Code style

- Bash with `set -Eeuo pipefail` in entry points, and shellcheck-clean.
- Comments explain *why*, often which outage taught the lesson, not *what*.
- Messages to users are short and say what to do next.
- Python uses the standard library only, version 3.11 or newer.
- Documentation follows the same voice as the existing docs: short sentences, active voice, and code blocks with a language tag for every command.

## Commits

- One logical change per commit.
- A short summary in the imperative mood ("Add", "Fix", not "Added"), under about 72 characters. An area prefix is welcome when it helps: `docs: ...`, `vaultwarden: ...`.
- A body that explains why the change is needed, when the summary doesn't make it obvious.
- Commit with your GitHub noreply address if you don't want your email in the public history. The privacy scan accepts `users.noreply.github.com` addresses.

## Pull requests

Before you open a pull request, check that:

- [ ] `bats tests/bats` and `python3 -m unittest discover -s tests/python` pass.
- [ ] shellcheck is clean.
- [ ] `python3 scripts/privacy-scan.py` passes.
- [ ] You tested on a real device, and say which model and Android version, or say that you didn't.
- [ ] `MOD_TESTED` and [docs/testing.md](docs/testing.md) are updated if coverage changed.
- [ ] Documentation matches the change: commands, flags, ports, paths and module names.

The pull request template repeats this checklist. Small, focused pull requests are reviewed fastest.

## Submitting a device report

1. Install resurrect on the device and let it run, ideally for a day.
2. Collect the device details. The output contains no serial numbers, IDs or network addresses:

   ```bash
   rez device --report
   ```

3. Collect the state of each module:

   ```bash
   rez status
   rez doctor
   ```

4. Open a [device report](https://github.com/JathinYanna04/resurrect/issues/new?template=device-report.yml) and paste the output. Say which modules worked, MemAvailable after a day, whether everything came back after a reboot, and any vendor settings you had to change.

Reported devices are listed in [docs/tested-devices.md](docs/tested-devices.md).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `pre-commit` fails with a denylist entry number | A staged file contains one of your denylisted strings | Remove it. If it is a string you mean to publish, add the exact string to your local allowlist |
| `commit-msg: commit message or author identity failed the privacy scan` | Your commit email or name matches a pattern or your denylist | Commit with your GitHub noreply address, or allowlist that exact address |
| The hooks don't run | `core.hooksPath` is not set | Run `git config core.hooksPath scripts/hooks` |
| `rez setup must run inside Termux` | You ran setup on a normal Linux machine | Set `REZ_ALLOW_NON_TERMUX=1` and use `--dry-run` |
