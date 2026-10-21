# DNS and AdGuard Home

AdGuard Home blocks ads and trackers for every device that uses it as its DNS server. A phone is a great place to run it, as long as you remember that **phones reboot, crash, run out of battery and drop off Wi-Fi**.

## The one rule

**Never make the phone the only DNS resolver for your other devices.**

If a device sends all its DNS to the phone and the phone goes away, that device loses the internet: web pages, apps, even Tailscale's own coordination can fail. resurrect never configures other devices for you, and the setup screen repeats this warning.

## What went wrong once (and why the rule exists)

A phone running AdGuard was set as the tailnet-wide DNS server in Tailscale, with "Override local DNS" on, so every device on the tailnet sent all lookups to it. During a routine reboot test:

1. The phone rebooted; AdGuard was down for about a minute until it started again. Every device lost DNS for that minute.
2. On a second reboot, AdGuard **did not start at all**. Its launcher checked "is my old PID still alive?", but after the reboot Android had given that PID to an unrelated system process. As root, `kill -0` succeeded on that process, so the launcher concluded AdGuard was already running and did nothing.
3. Every device on the tailnet lost name resolution until someone switched Tailscale off on the laptop and removed the global nameserver.

Fixes that are now built into resurrect:

- "Is it running" checks read `/proc/<pid>/cmdline`. A pidfile is never trusted on its own.
- The monitor queries AdGuard with a real DNS lookup every minute and alerts after two failures.
- The **fallback approach** below replaced tailnet-wide DNS.

## Root vs no root

| | Root | No root |
|---|---|---|
| DNS port | 53 | 5335 (`adguard.dns_port`) |
| Started by | Magisk at boot (works even if Termux is broken) | resurrect's boot script, under a supervisor |
| Clients | Any device can use it directly (with the caveats above) | Clients need a forwarder that can use a custom port (the laptop setup below), or a router that supports custom DNS ports |

Android doesn't let apps listen on ports below 1024, which is why the no-root version can't use 53.

## First-time setup

There is no setup wizard to click through. AdGuard's wizard refuses to start unless it can bind privileged ports, which an app without root never can, so resurrect writes the initial configuration itself:

- Admin UI on port 3000, user `admin`, generated password: `rez adguard show-password`.
- DNS on port **53** (root) or **5335** (no root).
- Upstreams: Quad9 and Cloudflare over DNS-over-HTTPS, load-balanced, DNSSEC on, bootstrap `9.9.9.9` / `1.1.1.1`.
- Blocklist: the AdGuard DNS filter.
- Query log and statistics kept for 24 hours (keeps the database small).

Check it: `rez adguard test`. Then open `http://<phone>:3000` over Tailscale to change anything. AdGuard owns the file from then on.

Want more blocking? Add one of the HaGeZi lists (https://github.com/hagezi/dns-blocklists) under Filters > DNS blocklists. Bigger lists cost RAM (100k rules is roughly 25 MB).

resurrect starts AdGuard with `SSL_CERT_FILE` pointing at Termux's CA bundle (and Android's store as a fallback). Without it, AdGuard's Linux build finds no certificates on Android and every DNS-over-HTTPS upstream fails with "certificate signed by unknown authority".

## Using it safely: the fallback approach

Run a small forwarder on each computer that **tries the phone first and falls back to a public resolver automatically**. Step-by-step setup (Linux, macOS, Windows), plus how to prove the fallback works: [extras/laptop/README.md](../extras/laptop/README.md#use-the-phones-adguard-without-risking-your-internet).

Two details matter:

- **Use TCP to reach the phone.** With built-in (userspace) Tailscale, inbound UDP forwarding has crashed tailscaled. The forwarder config uses `tcp://`. resurrect's monitor also probes over TCP.
- **The phone itself never uses its own AdGuard** (`--accept-dns=false` for tailscaled). A device that resolves through a service running on itself can't recover when that service is down.

### If you still want Tailscale-wide DNS

You can set the phone as a global nameserver in the Tailscale admin console (DNS page). If you do:

- Keep "Override local DNS" **off**, so devices keep their normal resolver as a fallback. With it on, the phone becomes the only resolver for every device.
- Learn the emergency steps below **before** you need them.

## Emergency: names stop resolving

1. **Tailscale-wide DNS:** open https://login.tailscale.com/admin/dns from any device that still works (a phone on mobile data with Tailscale off is fine) and turn off "Override local DNS", or remove the phone's address. Devices fall back to their normal DNS within seconds.
2. **One device, right now:** `tailscale set --accept-dns=false`. In the Android/iOS app: Settings > Use Tailscale DNS off.
3. **A computer using the forwarder:** `sudo bash extras/laptop/dns-fallback/undo-linux.sh`, or set DNS back to automatic.
4. Then fix AdGuard: `rez status`, `rez logs adguard` (root mode: `su -c 'tail /data/adb/resurrect/adguard/agh.log'`), `rez adguard test`.
