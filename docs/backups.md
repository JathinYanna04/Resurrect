# Backups and restore

This guide explains what the `backup` module saves, how resurrect checks that backups can be restored, how to get copies off the device, and how to restore, either on the same device or on a new one. Read it once after setup, and keep it handy for the day a device dies.

## Contents

- [Prerequisites](#prerequisites)
- [What runs and when](#what-runs-and-when)
- [What's in an archive](#whats-in-an-archive)
- [Copy backups off the device](#copy-backups-off-the-device)
- [Test a restore](#test-a-restore)
- [Restore on the same device](#restore-on-the-same-device)
- [Restore on a new device](#restore-on-a-new-device)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- The `backup` module installed (it is in every profile).
- `ntfy` installed, so failures reach you.
- For off-device copies: a computer that can reach the device over SSH. See [extras/laptop/README.md](../extras/laptop/README.md).

## What runs and when

| When | Command | What it does |
|---|---|---|
| Daily at 03:30 | `rez backup run` | Writes one archive, `~/resurrect-backups/resurrect-<date>_<time>.tar.gz`, plus a `.sha256` file, and keeps the newest `backup.keep` archives (default 7) |
| Sundays at 05:15 | `rez backup verify` | Restore test of the newest archive in a scratch folder |
| Daily, on your computer | `extras/laptop/pull-backups.sh` | Copies the archives off the device and verifies them |

A failed backup or restore test sends an ntfy alert. The `monitor` module also alerts when no backup has succeeded for 36 hours and, with `backup.expect_pull=yes`, when no computer has pulled a copy for 3 days.

To run a backup now and list what you have:

```bash
rez backup run
rez backup list
```

## What's in an archive

Each module decides what to back up, and copies SQLite databases with `.backup`, which is consistent while the service runs.

| Module | Contents |
|---|---|
| `base` | `resurrect.conf`, `authorized_keys`, `sshd_config`, the crontab |
| `tailscale` | Node state, so a restored device keeps its tailnet identity and address without a new login |
| `ntfy` | `server.yml` and the user database |
| `vaultwarden` | Database, RSA keys, attachments, Sends, `config.json` and the admin token hash |
| `adguard` | `AdGuardHome.yaml`. Filter lists and logs are downloaded or rebuilt |
| `copyparty` | Its config file |
| `filebrowser` | Its database (users and settings) |
| `syncthing` | `config.xml`, `cert.pem` and `key.pem`, which together hold the device ID |
| `alerts` | Job files and the state database (items already seen) |
| `jellyfin` | Library database and settings, without metadata images or cache |

Each archive also has a `MANIFEST` file listing the resurrect version, the date and the modules.

> [!WARNING]
> **Your files are not in these archives.** Shared folders, synced folders and media are left out. Back them up separately, or let Syncthing keep a copy on another device. Binaries are left out too; they are downloaded and verified again on reinstall.

Archives contain sensitive data: password hashes, keys and Tailscale node state. They do **not** contain resurrect's secrets folder (`~/.config/resurrect/secrets/`), so the generated passwords are not in them. Save the passwords you need in Vaultwarden (see [security.md](security.md#hardening-checklist)).

## Copy backups off the device

A backup that only lives on the device dies with it. On your computer, run `pull-backups.sh` daily. It copies new archives over SSH, checks each one against its checksum, never deletes a copy because the device lost it, and tells the device a pull succeeded. Setup and scheduling are in [extras/laptop/README.md](../extras/laptop/README.md#pull-backups-off-the-device).

## Test a restore

```bash
rez backup verify                       # the newest archive
rez backup verify ~/resurrect-backups/resurrect-2026-01-01_0330.tar.gz
```

The test checks the archive's checksum, extracts it to a scratch folder and runs each module's check, for example SQLite's `integrity_check` and Vaultwarden's user count. It touches nothing live. Expected output:

```text
verify resurrect-2026-01-01_0330.tar.gz
  base: ok
  ntfy: ok
  vaultwarden: ok (users: 1)
 ok restore test passed
```

## Restore on the same device

Use this when a service's data is damaged but resurrect itself still works. The order is always: stop the module, put the files back, start it.

1. Extract the archive:

   ```bash
   rez backup extract ~/resurrect-backups/resurrect-2026-01-01_0330.tar.gz ~/restore
   ls ~/restore
   ```

   You get one folder per module, plus `MANIFEST`.

2. Restore the module you need. On the same device the secrets folder still matches, so every module's files can go back as they are.

   **Vaultwarden:**

   ```bash
   rez stop vaultwarden
   d=~/.local/share/resurrect/vaultwarden/data
   cp ~/restore/vaultwarden/db.sqlite3 ~/restore/vaultwarden/rsa_key* "$d/"
   cp -r ~/restore/vaultwarden/attachments ~/restore/vaultwarden/sends "$d/" 2>/dev/null
   cp ~/restore/vaultwarden/config.json "$d/" 2>/dev/null
   rez start vaultwarden
   ```

   **ntfy:**

   ```bash
   rez stop ntfy
   cp ~/restore/ntfy/user.db ~/.local/share/resurrect/ntfy/
   rez start ntfy
   ```

   **AdGuard Home** (no root):

   ```bash
   rez stop adguard
   cp ~/restore/adguard/AdGuardHome.yaml ~/.local/share/resurrect/adguard/
   rez start adguard
   ```

   In root mode the file goes to `/data/adb/resurrect/adguard/` instead:

   ```bash
   rez stop adguard
   su -c "cp $HOME/restore/adguard/AdGuardHome.yaml /data/adb/resurrect/adguard/"
   rez start adguard
   ```

   **Smart alerts:**

   ```bash
   cp ~/restore/alerts/jobs/*.toml ~/.config/resurrect/alerts/
   cp ~/restore/alerts/alerts.db ~/.local/state/resurrect/
   rez alerts sync
   ```

3. Check the result:

   ```bash
   rez status
   rez doctor
   ```

## Restore on a new device

The new device gets a fresh install with the same settings, then you put the data back. Because the secrets folder is not in the archive, the new install generates new passwords; the table in step 7 explains what that means for each module.

1. Install Termux and Termux:Boot from the same source (F-Droid or GitHub), and open Termux:Boot once.
2. Download resurrect without starting setup:

   ```bash
   pkg update -y && pkg install -y git
   git clone https://github.com/JathinYanna04/Resurrect ~/.resurrect
   ```

3. Copy the archive to the device. One way: give Termux storage access with `termux-setup-storage`, move the archive into the device's Downloads folder, then:

   ```bash
   cp ~/storage/downloads/resurrect-2026-01-01_0330.tar.gz ~/
   ```

4. Extract it and put your old settings in place:

   ```bash
   bash ~/.resurrect/bin/rez backup extract ~/resurrect-2026-01-01_0330.tar.gz ~/restore
   mkdir -p ~/.config/resurrect
   cp ~/restore/base/resurrect.conf ~/.config/resurrect/resurrect.conf
   ```

   If the new device has no root but the old one had, edit the file first: set `device.root=no` and `adguard.mode=noroot`, and remove `acc` from the `modules=` line.

5. Reinstall the same modules with the same answers:

   ```bash
   bash ~/.resurrect/bin/rez --yes install $(sed -n 's/^modules=//p' ~/.config/resurrect/resurrect.conf | tr ',' ' ')
   ```

   The SSH key you gave during setup is saved in the config file, so it is added again. Keys you added later with `rez base add-key` are only in the archive; put them back with:

   ```bash
   cp ~/restore/base/authorized_keys ~/.ssh/authorized_keys
   ```

6. Restore Tailscale's node state, so the device keeps its tailnet name and address:

   ```bash
   rez stop tailscale
   root=$PREFIX/var/lib/proot-distro/containers/debian/rootfs
   [ -d "$root" ] || root=$PREFIX/var/lib/proot-distro/installed-rootfs/debian
   cp ~/restore/tailscale/tailscaled.state "$root/var/lib/tailscale/"
   rez start tailscale
   ```

7. Restore each module's data:

   | Module | What to do |
   |---|---|
   | `vaultwarden` | Restore the database, keys, attachments and Sends as in [Restore on the same device](#restore-on-the-same-device). Don't restore `admin_token`: the `/admin` password is new (`rez vaultwarden show-admin-password`). Your vault and account password are unchanged |
   | `ntfy` | Don't restore `user.db`. The new install created the users with new credentials, and the old database doesn't contain the token resurrect now publishes with. In the ntfy app, update the `phone` password (`rez ntfy show-phone-password`) |
   | `adguard` | Restoring `AdGuardHome.yaml` brings back your filters and settings, and also the **old** admin password. Restore it only if you saved that password |
   | `syncthing` | Stop Syncthing and copy `config.xml`, `cert.pem` and `key.pem` into `~/.local/share/resurrect/syncthing/` to keep the same device ID, so your other devices reconnect. The GUI password is then the old one |
   | `copyparty`, `filebrowser` | Nothing to restore: the new install has the same settings and a new password |
   | `alerts` | Restore the jobs and state database as in [Restore on the same device](#restore-on-the-same-device) |
   | `jellyfin` | Stop Jellyfin and extract `jellyfin.tar` into `/var/lib/jellyfin` inside Debian |

8. Check everything, then reboot once to confirm it all comes back:

   ```bash
   rez status
   rez doctor
   ```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `a backup is already running` | Another `rez backup run` holds the lock | Wait for it to finish |
| Alert: `Backup failed` with a module name | That module's backup step failed | Read `~/.local/state/resurrect/logs/backup.log`. Often the disk is full (`rez status`) |
| `checksum mismatch` from `rez backup verify` | The archive is damaged | Use an older archive, or a copy from your computer |
| Alert: `no successful backup in 36 h` | The nightly cron job isn't running | Check that crond runs (`rez status`, under `base`), then `rez cron sync` |
| Alert: `backups have not left the phone for 3 days` | No computer pulled a copy | Check the pull job on your computer. Set `backup.expect_pull=no` if you copy backups another way |
| `no backup found` | No archive yet, or a different `backup.dir` | Run `rez backup run`, and check `backup.dir` in the config file |
