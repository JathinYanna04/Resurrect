# shellcheck shell=bash
# adguard: AdGuard Home network-wide ad blocking.
#
#   root:    real DNS port 53, started by Magisk at boot (independent of
#            Termux), so phones and laptops can point at it directly.
#   no root: Android does not let apps bind ports below 1024, so DNS listens
#            on a high port (5335). Clients need a small forwarder; see
#            docs/dns-and-adguard.md and extras/laptop/dns-fallback/.
#
# NEVER make this phone the only DNS resolver for other devices. When it
# reboots, crashes or loses Wi-Fi, every device that depends on it loses
# the internet. Always configure a fallback resolver (the docs show how).

MOD_NAME=adguard
MOD_DESC="AdGuard Home ad blocking (port 53 with root, high port without)"
MOD_ROOT=optional
MOD_DEPENDS="base"
MOD_PORTS="5335 3000"
MOD_RAM_EST_MB=110
MOD_DISK_EST_MB=40
MOD_TESTED="termux-docker (amd64): no-root install, start, login, DNS. Root mode and Magisk launcher: real device only"

AGH_USER_DIR=$REZ_DATA_DIR/adguard
AGH_ROOT_DIR=/data/adb/resurrect/adguard
AGH_LAUNCHER=/data/adb/service.d/resurrect-adguard.sh

_mode() { cfg_get adguard.mode noroot; }
_dns_port() { if [[ "$(_mode)" == root ]]; then echo 53; else cfg_get adguard.dns_port 5335; fi; }
_ui_port() { cfg_get adguard.ui_port 3000; }
_dir() { if [[ "$(_mode)" == root ]]; then echo "$AGH_ROOT_DIR"; else echo "$AGH_USER_DIR"; fi; }

mod_configure() {
  local mode
  mode=$(cfg_get adguard.mode "")
  if [[ -z "$mode" ]]; then
    mode=noroot
    if [[ "$REZ_HAS_ROOT" == yes ]] && ui_yesno "AdGuard Home" \
      "Root is available. Run AdGuard on the real DNS port 53, started by Magisk at boot?" yes; then
      mode=root
    fi
  fi
  [[ "$mode" == root && "$REZ_HAS_ROOT" != yes ]] && die "adguard.mode=root needs root"
  cfg_set adguard.mode "$mode"
  ui_msg "DNS safety" "Never make this phone the ONLY DNS server for your other devices.
If it reboots or crashes, they all lose the internet.

Use it as the first resolver with a fallback (docs/dns-and-adguard.md shows a laptop setup that falls back automatically), and keep the emergency switch-off steps handy."
}

_launcher() {
  cat <<EOF
#!/system/bin/sh
# AdGuard Home for resurrect. Run as root by Magisk at every boot.
# Written by rez; edit with: rez adguard reinstall
D=$AGH_ROOT_DIR
# Go build: tell it where CA certificates are, or every DoH upstream fails.
export ${TLS_ENV[0]} ${TLS_ENV[1]}
until [ "\$(getprop sys.boot_completed)" = 1 ]; do sleep 5; done
# Only trust the pidfile if that PID really is AdGuardHome: after a reboot
# Android reuses PIDs, and as root a plain kill -0 succeeds on any process.
if [ -f \$D/agh.pid ]; then
  p=\$(cat \$D/agh.pid)
  tr '\\0' ' ' < /proc/\$p/cmdline 2>/dev/null | grep -q "\$D/AdGuardHome" && exit 0
  rm -f \$D/agh.pid
fi
cd \$D || exit 1
nohup \$D/AdGuardHome -w \$D -c \$D/AdGuardHome.yaml --pidfile \$D/agh.pid --no-check-update \\
  --web-addr $(service_bind):$(_ui_port) >> \$D/agh.log 2>&1 < /dev/null &
EOF
}

# _config: AdGuard's first-run wizard refuses to start unless it can bind
# privileged ports, which an app without root never can. So resurrect writes
# the config itself (AdGuard fills in every other setting with its defaults
# and upgrades the file). Password: rez adguard show-password.
_config() {
  local hash
  hash=$(secret_ensure adguard_password 20 | python3 -c 'import sys, bcrypt
print(bcrypt.hashpw(sys.stdin.read().encode(), bcrypt.gensalt(10)).decode())') \
    || die "bcrypt not available (pkg install python-bcrypt)"
  cat <<EOF
# Written by rez on first install; AdGuard Home owns this file from now on.
http:
  address: $(service_bind):$(_ui_port)
users:
  - name: admin
    password: $hash
dns:
  bind_hosts:
    - 0.0.0.0
  port: $(_dns_port)
  upstream_dns:
    - https://dns.quad9.net/dns-query
    - https://cloudflare-dns.com/dns-query
  upstream_mode: load_balance
  bootstrap_dns:
    - 9.9.9.9
    - 1.1.1.1
  cache_optimistic: true
  enable_dnssec: true
filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter
    id: 1
querylog:
  interval: 24h
statistics:
  interval: 1d
schema_version: $PIN_ADGUARD_SCHEMA
EOF
}

mod_install() {
  local tgz work
  is_termux && run_cmd pkg install -y python-bcrypt
  tgz=$(fetch_pinned adguard)
  [[ "$REZ_DRY_RUN" == 1 ]] && return 0
  work=$(mktemp -d)
  tar -xzf "$tgz" -C "$work"
  if [[ "$(_mode)" == root ]]; then
    _launcher >"$work/launcher.sh"
    _configured || _config >"$work/AdGuardHome.yaml"
    as_root "mkdir -p $AGH_ROOT_DIR /data/adb/service.d && chmod 700 $AGH_ROOT_DIR \
      && cp $work/AdGuardHome/AdGuardHome $AGH_ROOT_DIR/ && chmod 700 $AGH_ROOT_DIR/AdGuardHome \
      && cp $work/launcher.sh $AGH_LAUNCHER && chmod 755 $AGH_LAUNCHER \
      && { [ ! -f $work/AdGuardHome.yaml ] || install -m 600 $work/AdGuardHome.yaml $AGH_ROOT_DIR/AdGuardHome.yaml; }"
  else
    ensure_dir 700 "$AGH_USER_DIR"
    install -m 755 "$work/AdGuardHome/AdGuardHome" "$AGH_USER_DIR/AdGuardHome"
    _configured || _config | atomic_write "$AGH_USER_DIR/AdGuardHome.yaml" 600
  fi
  rm -rf "$work"
  ok "AdGuard Home $PIN_ADGUARD_VERSION installed ($(_mode) mode, DNS port $(_dns_port))"
}

_root_pid() {
  as_root "p=\$(cat $AGH_ROOT_DIR/agh.pid 2>/dev/null) && tr '\\0' ' ' < /proc/\$p/cmdline 2>/dev/null | grep -q $AGH_ROOT_DIR/AdGuardHome && echo \$p" 2>/dev/null
}

mod_start() {
  if [[ "$(_mode)" == root ]]; then
    if [[ -n "$(_root_pid)" ]]; then ok "adguard already running"; return 0; fi
    as_root "sh $AGH_LAUNCHER"
    [[ "$REZ_DRY_RUN" == 1 ]] && return 0
    sleep 3
    if [[ -z "$(_root_pid)" ]]; then
      err "adguard did not start; log: su -c 'tail $AGH_ROOT_DIR/agh.log'"
      return 1
    fi
    ok "adguard started"
    return 0
  fi
  SVC_ENV=("${TLS_ENV[@]}")
  SVC_SUPERVISE=1 svc_start adguard AdGuardHome "" -- "$AGH_USER_DIR/AdGuardHome" -w "$AGH_USER_DIR" \
    -c "$AGH_USER_DIR/AdGuardHome.yaml" --no-check-update --web-addr "$(service_bind):$(_ui_port)"
}

mod_stop() {
  if [[ "$(_mode)" == root ]]; then
    local p
    p=$(_root_pid)
    if [[ -n "$p" ]]; then as_root "kill $p" && ok "adguard stopped"
    else ok "adguard not running"
    fi
    return 0
  fi
  svc_stop adguard AdGuardHome
}

_configured() {
  if [[ "$(_mode)" == root ]]; then as_root "test -f $AGH_ROOT_DIR/AdGuardHome.yaml"
  else [[ -f "$AGH_USER_DIR/AdGuardHome.yaml" ]]
  fi
}

_dns_ok() { python3 "$REZ_ROOT/lib/dnsprobe.py" 127.0.0.1 "$(_dns_port)" >/dev/null 2>&1; }

mod_status() {
  local extra
  extra="DNS :$(_dns_port), UI :$(_ui_port)"
  if [[ "$(_mode)" == root ]]; then
    local p
    p=$(_root_pid)
    if [[ -n "$p" ]]; then printf '%-14s %srunning%s  pid %-7s %s (root)\n' adguard "$_c_grn" "$_c_off" "$p" "$extra"
    else printf '%-14s %sstopped%s  %-11s %s (root)\n' adguard "$_c_red" "$_c_off" "" "$extra"; return 1
    fi
    return 0
  fi
  svc_status_line adguard AdGuardHome "" "$extra"
}

mod_health() {
  _dns_ok || { echo "no DNS answer on port $(_dns_port)"; return 1; }
}

mod_backup() {
  mkdir -p "$1"
  if [[ "$(_mode)" == root ]]; then
    as_root "cat $AGH_ROOT_DIR/AdGuardHome.yaml" >"$1/AdGuardHome.yaml" 2>/dev/null || rm -f "$1/AdGuardHome.yaml"
  else
    cp -a "$AGH_USER_DIR/AdGuardHome.yaml" "$1/" 2>/dev/null || true
  fi
  return 0
}

mod_restore_check() {
  [[ -f "$1/AdGuardHome.yaml" ]] || return 0
  grep -q '^dns:' "$1/AdGuardHome.yaml"
}

mod_uninstall() {
  if [[ "$(_mode)" == root ]]; then
    as_root "rm -f $AGH_LAUNCHER $AGH_ROOT_DIR/AdGuardHome"
    [[ "${REZ_PURGE:-0}" == 1 ]] && as_root "rm -rf $AGH_ROOT_DIR"
  else
    run_cmd rm -f "$AGH_USER_DIR/AdGuardHome"
    [[ "${REZ_PURGE:-0}" == 1 ]] && run_cmd rm -rf "$AGH_USER_DIR"
  fi
  return 0
}

mod_info() {
  printf 'AdGuard:    http://%s:%s  user admin, password: rez adguard show-password; DNS on port %s\n' \
    "$(device_host)" "$(_ui_port)" "$(_dns_port)"
  printf '            Before pointing devices at it, read docs/dns-and-adguard.md (fallback + emergency steps).\n'
}

mod_cli() {
  case "${1:-}" in
    test) if _dns_ok; then ok "AdGuard answers DNS on port $(_dns_port)"; else err "no DNS answer on port $(_dns_port)"; return 1; fi ;;
    reinstall) mod_stop; mod_install; mod_start ;;
    show-password) secret_get adguard_password; echo ;;
    *) die "usage: rez adguard test|show-password|reinstall" ;;
  esac
}
