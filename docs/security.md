# Security

This page explains what resurrect does by default to protect a device that holds your passwords and files, where those defaults have limits, and the steps that are left to you. Read it after your first `rez setup`, and again before you share your tailnet with anyone or publish a service with Cloudflare Tunnel.

To report a vulnerability in resurrect itself, see [SECURITY.md](../SECURITY.md).

## Prerequisites

- resurrect installed with at least the `base` module.
- For the hardening steps: access to the Tailscale admin console and to each service's web interface.

## Defaults

| Area | What resurrect does |
|---|---|
| Remote access | Tailscale only. Nothing is port-forwarded, and nothing is public unless you install `cloudflared` and publish a service yourself |
| SSH | Key login only. `rez install base` sets `PasswordAuthentication no` and `KbdInteractiveAuthentication no` in Termux's `sshd_config`. sshd does not start until a key is in `~/.ssh/authorized_keys` |
| Web interfaces | With built-in Tailscale (`tailscale.mode=proot`) they listen on `127.0.0.1`, so they are reachable over your tailnet but not from the Wi-Fi network. With the Tailscale app they listen on all interfaces and rely on their logins. `net.bind` overrides this |
| ntfy | `auth-default-access: deny-all`. Three users: `admin` for you, `rez` with a publish-only token that resurrect uses, and `phone` with read-only access for the ntfy app |
| Vaultwarden | HTTPS only. Sign-ups are open until the first account exists; a cron job then closes them within 5 minutes and confirms that a test registration is refused. Invitations and password hints are off. The `/admin` token is stored as an argon2id hash |
| AdGuard Home, copyparty, File Browser, Syncthing | An `admin` login with a generated password |
| Secrets | One file per secret in `~/.config/resurrect/secrets/` (folder mode 700, files mode 600). Never written to the config file or the logs |
| Downloads | Every binary resurrect downloads is pinned to a version and verified with SHA-256 (Vaultwarden by image digest). A mismatch aborts the install |
| Backups | The backup folder is mode 700 and archives are created with `umask 077` |
| Config file | Parsed as `key=value`, never executed, so `$(...)` in it does nothing |

## Limits of the defaults

### Built-in Tailscale exposes everything on localhost

Built-in Tailscale runs in userspace networking mode and hands incoming tailnet connections to `127.0.0.1`. That is what makes the `127.0.0.1` binding work, but it also means **every service listening on localhost is reachable by every device in your tailnet**, including anything you start yourself, such as a database or a debug server. If other people are in your tailnet, restrict access with [Tailscale access controls](https://tailscale.com/kb/1018/acls).

### Some ports always listen on every interface

| Port | Service | Why |
|---|---|---|
| 8022 | sshd | Termux's sshd listens on all interfaces. Login is key-only |
| 5335 or 53 | AdGuard Home DNS | Clients on your network must reach it |
| 22000 | Syncthing sync protocol | Syncthing's default, so peers can connect directly |
| 8096 | Jellyfin | Jellyfin's default. Restrict it under Dashboard > Networking |

> [!WARNING]
> Jellyfin is not configured with a password by resurrect. Its first-run wizard is open to anyone who can reach port 8096 until you complete it, so finish the wizard right after `rez install jellyfin`.

### Termux apps share one Android user

Every process in Termux runs as the same Android user, so a compromised service could read the other services' data and the secrets folder. Don't run untrusted code in the same Termux installation. Android's app sandbox still separates Termux from your other apps.

A few services keep their own copy of a credential because they need it to run: copyparty's password is in its config file, AdGuard Home stores a bcrypt hash, and Vaultwarden's environment file holds the admin token hash. All of these files are mode 600. Two one-time setup commands, Syncthing's `generate` and File Browser's `users add`, receive the generated password as an argument for the moment they run.

### Packages that are not pinned

Termux packages (including `syncthing` and `cloudflared`), the Debian packages inside proot, and Jellyfin (from Jellyfin's signed apt repository) are verified by their package managers' signatures, not by checksums pinned in resurrect.

### Physical access

Use a screen lock. Android's file-based encryption only protects data at rest until the device is unlocked for the first time after a restart. Anyone with physical access to an unlocked, rooted device can read everything on it.

## Hardening checklist

1. **Store the generated passwords** in Vaultwarden, then change them in each service's interface if you like:

   ```bash
   rez vaultwarden show-admin-password
   rez ntfy show-admin-password
   rez ntfy show-phone-password
   rez adguard show-password
   rez copyparty show-password
   rez filebrowser show-password
   rez syncthing show-password
   ```

2. **Turn on two-step login in Vaultwarden**: web vault > Settings > Security > Two-step login. resurrect can't do this for you.

3. **Confirm that Vaultwarden sign-ups are closed** once your account exists. `rez status` shows `sign-ups: closed`. To close them by hand:

   ```bash
   rez vaultwarden close-signups
   ```

   Expected output ends with:

   ```text
    ok sign-ups closed (a test registration was refused)
   ```

4. **Use a Tailscale certificate for Vaultwarden.** Enable HTTPS certificates in the Tailscale admin console (DNS page). If you chose a self-signed certificate instead, Bitwarden apps only connect after you install `~/.local/share/resurrect/vaultwarden/tls/cert.pem` as a trusted certificate on each device.

5. **Restrict your tailnet** with access controls if anyone else is in it.

6. **Publish nothing you don't have to.** If you use Cloudflare Tunnel, put Cloudflare Access in front of every hostname and never publish Vaultwarden's `/admin`, AdGuard Home, the Syncthing GUI, File Browser or ntfy's admin account. See [remote-access.md](remote-access.md#cloudflare-tunnel-optional-public).

7. **Keep backups private.** Archives contain password hashes, keys and Tailscale node state. Treat every copy like the device itself. See [backups.md](backups.md).

8. **Grant root only if you need it.** Root lets a compromised app do far more. Grant Termux root only for the root-only features, and never grant it to apps you don't need. See [rooting.md](rooting.md).

## Updates

`pkg upgrade` updates Termux packages. Pinned binaries (Tailscale, ntfy, Vaultwarden, AdGuard Home, File Browser, copyparty) change when resurrect updates its pins:

```bash
git -C ~/.resurrect pull
rez install vaultwarden        # repeat for each module whose pin changed
```

The [changelog](../CHANGELOG.md) lists pin changes. Watch Vaultwarden's security advisories in particular.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `warn argon2 not found: the admin token is stored in plain text` | The `argon2` package could not be installed | Run `pkg install argon2`, delete `~/.local/share/resurrect/vaultwarden/admin_token`, run `rez install vaultwarden`, then `rez restart vaultwarden` |
| `sign-ups were turned off but a test registration was NOT refused` | Vaultwarden did not pick up the new setting | Run `rez restart vaultwarden`, then `rez vaultwarden close-signups` again, and check `/admin` |
| `doctor` reports `ssh password login is enabled` | `sshd_config` was changed after setup | Run `rez install base` to apply key-only login again |
| A Bitwarden app refuses to connect | Self-signed certificate not trusted on that device | Switch to a Tailscale certificate, or install `cert.pem` on the device |
