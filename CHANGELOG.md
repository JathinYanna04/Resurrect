# Changelog

All notable changes to resurrect are recorded here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Pinned upstream versions are listed with each release, because changing them means running `rez install <module>` again.

## [Unreleased]

## [0.1.1] - 2026-10-21

Bug fixes found while verifying the documentation against the code, and a full documentation rewrite. Pinned upstream versions are unchanged from 0.1.0.

### Fixed

- `rez stop`, `rez restart` and `rez uninstall` now stop every running copy of a service. Previously they stopped one, so a duplicate started by a second boot script survived and blocked the next start.
- `vaultwarden`: install `argon2`, so the `/admin` token is stored as an argon2id hash on real devices. Previously only the test image had `argon2`, and a real install stored the token in plain text with a warning.
- `alerts`: `rez alerts run JOB --dry-run` now passes `--dry-run` to the job. The global option parser consumed it, so a test run called the LLM, sent alerts and marked items as seen.
- `rez help` showed `alerts list|run_cmd JOB`; it now shows `run JOB` and `set-key`. Two other messages had the same leftover.
- `config/resurrect.conf.example`: comments are now on their own lines. Uncommenting a line with a trailing comment made the comment part of the value.

### Changed

- Rewrote all documentation, verified against the code, and added `CODE_OF_CONDUCT.md`, `SECURITY.md`, this changelog and `docs/tested-devices.md`.
- The Termux test image no longer pre-installs `argon2`, so the integration test covers the real install path.

## [0.1.0] - 2026-10-21

First public pre-release. Tested in the official Termux container, not yet on real devices.

### Added

- `rez` command-line tool with an interactive installer and a non-interactive mode (`--profile`, `--modules`, `--config`, `--yes`, `--dry-run`).
- Device detection (Android version, architecture, MemTotal and MemAvailable, storage, SD card, root, Termux source, Termux:Boot, the Android 12+ phantom process killer) with a Lite, Standard or Full profile recommendation.
- 14 modules: `base`, `tailscale`, `cloudflared`, `ntfy`, `vaultwarden`, `adguard`, `copyparty`, `filebrowser`, `syncthing`, `backup`, `monitor`, `alerts`, `jellyfin` and `acc` (root only).
- Reliability rules from a real device: a single locked boot script, `/proc/<pid>/cmdline` checks instead of trusted pidfiles, no self-matching process lookups, start only if not running, MemAvailable, supervised daemons, and DNS that never makes the device the only resolver.
- `rez device` with custom ROM guidance and links to official guides. Nothing is ever flashed, unlocked or rebooted automatically.
- Computer-side extras: verified backup pulls and a DNS forwarder with automatic fallback.
- Tests: bats and Python unit tests, a real install inside the Termux Docker image with 43 behaviour checks, shellcheck and a privacy scan in CI.

### Pinned versions

| Component | Version |
|---|---|
| Tailscale | 1.102.4 |
| ntfy | 2.32.0 |
| Vaultwarden | 1.37.4 (image digest) |
| AdGuard Home | 0.107.79 |
| File Browser | 2.63.23 |
| copyparty | 1.20.26 |
| ACC | v2023.10.16 |

[Unreleased]: https://github.com/JathinYanna04/Resurrect/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/JathinYanna04/Resurrect/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/JathinYanna04/Resurrect/releases/tag/v0.1.0
