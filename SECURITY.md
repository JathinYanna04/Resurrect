# Security policy

This page explains how to report a security vulnerability in resurrect privately, which versions receive fixes, and what is in scope. For how to run resurrect securely, see [docs/security.md](docs/security.md).

## Supported versions

resurrect is a pre-release. Security fixes go into the latest release and the `main` branch only.

| Version | Supported |
|---|---|
| 0.1.x | Yes |
| Older | No |

## Report a vulnerability

> [!WARNING]
> Please don't report security problems in public issues, discussions or pull requests.

Report vulnerabilities privately through GitHub's security advisories:

1. Open the repository's [**Security** tab](https://github.com/JathinYanna04/resurrect/security).
2. Choose **Report a vulnerability**, or go straight to the [new advisory form](https://github.com/JathinYanna04/resurrect/security/advisories/new).
3. Describe the problem, the affected version or commit, and the steps to reproduce it. Leave out real passwords, tokens and addresses.

Only the maintainers can see the report. You can discuss it with them in the advisory, and you are credited in the published advisory unless you prefer not to be.

This is a volunteer project. Reports are acknowledged as soon as possible, and fixes are released as quickly as their complexity allows. Please give the maintainers a reasonable chance to release a fix before disclosing the problem publicly.

## Scope

**In scope:** problems in resurrect's own code and defaults, for example:

- A service exposed beyond what [docs/security.md](docs/security.md) describes.
- Secrets leaked to logs, the config file, command lines of running services, backups outside their 700 folder, or device reports.
- A way around checksum verification of downloads.
- A way for `rez` to flash, unlock, reboot or gain root without the user's explicit action.
- Privacy scan gaps that let personal data into the repository.

**Out of scope:**

- Vulnerabilities in the services resurrect installs (Vaultwarden, AdGuard Home, ntfy, Tailscale and others). Report those to the upstream project.
- Limits that are already documented in [docs/security.md](docs/security.md#limits-of-the-defaults), such as all Termux processes sharing one Android user.
- Attacks that require physical access to an unlocked device.
