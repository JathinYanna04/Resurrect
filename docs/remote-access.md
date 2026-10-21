# Remote access

This guide covers how you reach your device's services from your other devices. Tailscale is the default and keeps everything private. Cloudflare Tunnel is optional and makes chosen services public. Read it when you set up the `tailscale` module, when a service won't open by name, or before you publish anything to the internet.

## Prerequisites

- resurrect installed with the `base` module.
- A free [Tailscale](https://tailscale.com) account, and Tailscale installed on the devices you connect from.
- For Cloudflare Tunnel only: a Cloudflare account with a domain.

## Choosing a Tailscale mode

Setup asks which mode to use. You can also set `tailscale.mode` in an answers file.

| | Built in (`proot`, default) | Android app (`app`) |
|---|---|---|
| How it runs | `tailscaled` in userspace networking mode inside proot Debian, started at boot with the other services | The official Tailscale app |
| Android VPN slot | Not used, so another VPN app still works | Used |
| HTTPS certificates for Vaultwarden | Yes, through `tailscale cert` | No (the app has no CLI) |
| Service binding | `127.0.0.1`: reachable over the tailnet, not from Wi-Fi | All interfaces, protected by each service's login |
| Supervision | Restarted with backoff and an alert if it exits | Managed by Android |

## Built-in mode

### 1. Log in

`rez install tailscale` installs Debian with proot-distro (about 150 MB) and the pinned Tailscale release. When the service starts and isn't logged in yet, it prints a login link. To log in later, or again:

```bash
rez tailscale up
```

Open the link on any device and approve the new machine. The device joins your tailnet as `resurrect` unless you set `tailscale.hostname`.

> [!TIP]
> For a non-interactive install, put a one-time [auth key](https://tailscale.com/kb/1085/auth-keys) in a file and set `tailscale.authkey_file` in your answers file. resurrect moves the key into its secrets folder and deletes it after the first successful login.

### 2. Check the connection

```bash
rez tailscale status
rez tailscale ip
```

`rez tailscale ip` prints the device's Tailscale IPv4 address (`100.x.y.z`). `rez status` shows `Running` and the device's tailnet name next to `tailscaled`.

### 3. Enable HTTPS certificates (for Vaultwarden)

1. In the Tailscale admin console, open the **DNS** page and enable **HTTPS Certificates**.
2. Issue the certificate:

   ```bash
   rez vaultwarden renew-cert
   ```

The certificate is for `<device>.<your-tailnet>.ts.net`. resurrect checks it every Monday and restarts Vaultwarden when it changes.

### How it behaves

- The device never uses tailnet DNS itself (`--accept-dns=false`), so it can't depend on a resolver that runs on itself.
- Incoming tailnet connections are handed to `127.0.0.1`. **Every service listening on localhost is reachable by your tailnet peers.** See [security.md](security.md#built-in-tailscale-exposes-everything-on-localhost).
- Userspace `tailscaled` has crashed on inbound UDP forwarding. It runs under a supervisor, and DNS traffic to the device should use TCP ([dns-and-adguard.md](dns-and-adguard.md#use-tcp-to-reach-the-device)).

## App mode

1. Install Tailscale from Google Play or F-Droid and sign in.
2. In Android settings, turn on **Always-on VPN** for Tailscale.
3. Set `tailscale.mode=app` (or pick it in setup). resurrect then only reminds you that the app manages the connection.

Services listen on all interfaces in this mode, so anyone on the same Wi-Fi network can reach their login pages. Use strong passwords.

## Opening services

`rez setup` prints every service's address when it finishes. With built-in Tailscale the addresses use the device's tailnet name.

> [!NOTE]
> Chrome and other browsers force HTTPS for every `*.ts.net` name. Services without TLS (AdGuard Home, ntfy, copyparty, File Browser, Syncthing, Jellyfin) fail to open by name with `ERR_SSL_PROTOCOL_ERROR`. Open them by Tailscale IP instead, for example `http://100.x.y.z:3000`. Vaultwarden uses HTTPS and opens by name.

| Service | Address |
|---|---|
| Vaultwarden | `https://<tailnet name>:8222` (admin page `/admin`) |
| AdGuard Home | `http://<tailscale ip>:3000` |
| ntfy | `http://<tailscale ip>:2586` |
| copyparty | `http://<tailscale ip>:3923` |
| File Browser | `http://<tailscale ip>:8085` |
| Syncthing | `http://<tailscale ip>:8384` |
| Jellyfin | `http://<tailscale ip>:8096` |
| SSH | `ssh -p 8022 <termux user>@<tailscale ip>` |

These are the default ports. Most can be changed in the config file (see [`config/resurrect.conf.example`](../config/resurrect.conf.example)).

## Cloudflare Tunnel (optional, public)

Use a tunnel only for a service you want reachable **from the internet without Tailscale**, such as sharing a copyparty folder with a friend.

> [!CAUTION]
> A tunnel puts a service on the public internet. Never publish Vaultwarden's `/admin`, AdGuard Home, the Syncthing GUI, File Browser or ntfy's admin account. Prefer Tailscale for anything personal.

1. In the Cloudflare dashboard, open **Zero Trust > Networks > Tunnels** and create a tunnel of type `cloudflared`. Copy the tunnel token (the long string after `--token`).
2. Install the module and paste the token when asked:

   ```bash
   rez install cloudflared
   ```

   The token is stored as a secret and passed to `cloudflared` through its environment, never on the command line. For a non-interactive install, set `cloudflared.token_file` in your answers file.
3. In the dashboard, add a public hostname that points to `http://localhost:PORT`.
4. Protect the hostname with Cloudflare Access (**Zero Trust > Access > Applications**). Without Access, anyone with the link reaches the service's login page.

Routes are managed in the Cloudflare dashboard, not by resurrect. `rez uninstall cloudflared` removes the token; delete the tunnel in the dashboard too.

> [!NOTE]
> The `cloudflared` module has not been tested yet. See [testing.md](testing.md).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `tailscale is not logged in yet: run rez tailscale up` | First start, or the node was removed from the tailnet | Run `rez tailscale up` and open the link |
| `tailscale cert failed: enable HTTPS certificates in the Tailscale admin console` | HTTPS certificates are off for your tailnet | Enable them on the DNS page, then run `rez vaultwarden renew-cert` |
| `ERR_SSL_PROTOCOL_ERROR` when opening `http://...ts.net` | Browsers force HTTPS for `.ts.net` | Open the service by Tailscale IP (`rez tailscale ip`) |
| Services reachable from Wi-Fi with app mode | Expected: app mode binds all interfaces | Built-in mode avoids this. Choose it during setup if services should only be reachable through Tailscale |
| `tailscaled` keeps restarting | It crashed, often on inbound UDP | Check `rez logs tailscaled`, and send DNS to the device over TCP |
| `cloudflared needs a tunnel token` | No token was given in non-interactive mode | Set `cloudflared.token_file`, or run `rez install cloudflared` interactively |

The `tailscale` module has not been tested on a real device yet. If something here doesn't match what you see, please [open an issue](https://github.com/JathinYanna04/Resurrect/issues/new?template=bug.yml).
