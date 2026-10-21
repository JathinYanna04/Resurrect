#!/usr/bin/env bash
# Use the phone's AdGuard Home on this Linux computer WITH an automatic
# fallback, so a phone that reboots, crashes or leaves Wi-Fi never takes
# your internet down.
#
#   sudo bash setup-linux.sh --phone ADDRESS [--port 5335] [--fallback tls://dns.quad9.net]
#                            [--networkmanager] [--tailscale]
#
#   ADDRESS  the phone's Tailscale IP or LAN IP
#   --port   53 if AdGuard runs in root mode, 5335 (default) without root
#   --networkmanager  stop NetworkManager from handing each Wi-Fi's DNS to
#                     systemd-resolved (otherwise those servers race AdGuard)
#   --tailscale       make Tailscale stop overriding DNS on this computer;
#                     *.ts.net names still resolve (forwarded to MagicDNS)
#
# How: systemd-resolved -> dnsproxy on 127.0.0.1:5353 -> the phone over TCP
# (UDP into userspace tailscaled has crashed it) -> if no answer within 2 s,
# the fallback resolver. Needs systemd-resolved and dnsproxy
# (https://github.com/AdguardTeam/dnsproxy; Arch: pacman -S dnsproxy).
# Undo everything: sudo bash undo-linux.sh
set -euo pipefail
phone='' port=5335 fallback=tls://dns.quad9.net nm=0 ts=0
while (($#)); do
  case "$1" in
    --phone) phone=${2:?}; shift ;;
    --port) port=${2:?}; shift ;;
    --fallback) fallback=${2:?}; shift ;;
    --networkmanager) nm=1 ;;
    --tailscale) ts=1 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
[[ -n "$phone" ]] || { echo "usage: sudo bash setup-linux.sh --phone ADDRESS [--port 5335]" >&2; exit 2; }
[[ $(id -u) == 0 ]] || { echo "run with sudo" >&2; exit 1; }
command -v dnsproxy >/dev/null || { echo "install dnsproxy first (see the header of this script)" >&2; exit 1; }
systemctl is-active --quiet systemd-resolved || { echo "systemd-resolved is not running; see README.md for other setups" >&2; exit 1; }

echo "1/3 dnsproxy service (phone first, $fallback as fallback)"
cat >/etc/systemd/system/resurrect-dnsproxy.service <<UNIT
[Unit]
Description=Local DNS forwarder: resurrect AdGuard on the phone first, public fallback
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=$(command -v dnsproxy) -l 127.0.0.1 -p 5353 \\
  -u tcp://$phone:$port -u "[/ts.net/]100.100.100.100" \\
  -f $fallback -b 9.9.9.9:53 --timeout=2s --cache --cache-optimistic
Restart=always
RestartSec=2
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now resurrect-dnsproxy.service

echo "2/3 systemd-resolved -> dnsproxy"
mkdir -p /etc/systemd/resolved.conf.d
cat >/etc/systemd/resolved.conf.d/zz-resurrect.conf <<'CONF'
# resurrect: all lookups go to the local dnsproxy (phone first, fallback after).
# Empty assignments clear DNS lists set by other drop-ins.
[Resolve]
DNS=
DNS=127.0.0.1:5353
FallbackDNS=
FallbackDNS=9.9.9.9#dns.quad9.net
Domains=~.
DNSOverTLS=no
CONF

if ((nm)); then
  echo "   NetworkManager: stop pushing per-network DNS into resolved"
  cat >/etc/NetworkManager/conf.d/zz-resurrect-dns.conf <<'CONF'
# resurrect: DNS comes from systemd-resolved's global setting only.
# Captive portals (hotel Wi-Fi) need the network's own DNS: remove this file
# and run: sudo systemctl reload NetworkManager
[main]
dns=none
systemd-resolved=false
CONF
  systemctl reload NetworkManager
fi
systemctl restart systemd-resolved

if ((ts)) && command -v tailscale >/dev/null; then
  echo "3/3 Tailscale: stop overriding DNS here (*.ts.net still works via dnsproxy)"
  tailscale set --accept-dns=false
else
  echo "3/3 Tailscale: unchanged"
fi

echo
echo "Done. Test: resolvectl query example.com"
echo "Then stop AdGuard on the phone (rez stop adguard) and query again: it must still resolve."
