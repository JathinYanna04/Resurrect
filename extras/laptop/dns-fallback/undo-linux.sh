#!/usr/bin/env bash
# Undo setup-linux.sh: back to your previous DNS setup.
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo "run with sudo" >&2; exit 1; }
systemctl disable --now resurrect-dnsproxy.service 2>/dev/null || true
rm -f /etc/systemd/system/resurrect-dnsproxy.service /etc/systemd/resolved.conf.d/zz-resurrect.conf
if [[ -f /etc/NetworkManager/conf.d/zz-resurrect-dns.conf ]]; then
  rm -f /etc/NetworkManager/conf.d/zz-resurrect-dns.conf
  systemctl reload NetworkManager
fi
systemctl daemon-reload
systemctl restart systemd-resolved
echo "Removed. If you used --tailscale and want Tailscale DNS back: tailscale set --accept-dns=true"
