# shellcheck shell=bash
# monitor: one lightweight loop that checks every module and the phone
# itself, and sends ntfy alerts. No extra server, a few MB of RAM.
#
# * A check must fail twice in a row before it alerts (no flapping).
# * Nothing alerts in the first 3 minutes after boot.
# * After an alert, the module is restarted once (monitor.autorestart).
# * A recovery message follows when the check passes again.

MOD_NAME=monitor
MOD_DESC="Health checks every minute with ntfy alerts and auto-restart"
MOD_DEPENDS="base"
MOD_RAM_EST_MB=5
MOD_TESTED="termux-docker: loop, alert-after-2, recovery, restart. Battery sensors: real device only"

MON_STATE=$REZ_STATE_DIR/monitor

_interval() { cfg_get monitor.interval 60; }

mod_start() {
  svc_start monitor rez "rez monitor loop" -- "$PREFIX/bin/bash" "$REZ_ROOT/bin/rez" monitor loop
}
mod_stop() { svc_stop monitor rez "rez monitor loop"; }
mod_status() { svc_status_line monitor rez "rez monitor loop" "every $(_interval)s, alerts via ntfy"; }
mod_health() { svc_running monitor rez "rez monitor loop"; }

_uptime_s() { awk '{ print int($1) }' "$REZ_PROC/uptime" 2>/dev/null || echo 9999; }

# _result NAME RC MESSAGE: count failures, alert on the 2nd, note recovery.
_result() {
  local name=$1 rc=$2 msg=$3 f n
  f="$MON_STATE/$name.fails"
  n=$(cat "$f" 2>/dev/null || echo 0)
  if ((rc == 0)); then
    if ((n >= 2)); then
      notify_send "$name recovered" "$name is healthy again." 3 white_check_mark
    fi
    rm -f "$f"
    return 0
  fi
  n=$((n + 1))
  echo "$n" >"$f"
  echo "$(date '+%F %T') $name failing ($n): $msg"
  if ((n == 2)) && (($(_uptime_s) > 180)); then
    notify_send "$name is down" "${msg:-health check failed}" 4 warning
    if [[ "$(cfg_get monitor.autorestart yes)" == yes ]] && module_exists "$name"; then
      module_call "$name" start >/dev/null 2>&1 || true
    fi
  fi
}

_battery() {
  local d=/sys/class/power_supply/battery t cap st
  if [[ -r "$d/temp" ]]; then
    t=$(( $(cat "$d/temp") / 10 )); cap=$(cat "$d/capacity" 2>/dev/null); st=$(cat "$d/status" 2>/dev/null)
  elif have termux-battery-status; then
    local j
    j=$(timeout 10 termux-battery-status 2>/dev/null) || return 0
    t=$(jq -r '.temperature | floor' <<<"$j"); cap=$(jq -r .percentage <<<"$j"); st=$(jq -r .status <<<"$j")
  else
    return 0
  fi
  printf '%s %s %s' "${t:-0}" "${cap:-0}" "${st:-unknown}"
}

monitor_once() {
  mkdir -p "$MON_STATE"
  local m out rc
  for m in $(modules_enabled); do
    [[ "$m" == monitor ]] && continue
    if [[ "$(cfg_get "$m.autostart" yes)" == no ]]; then continue; fi
    rc=0
    out=$(module_call "$m" health 2>&1) || rc=$?
    _result "$m" "$rc" "$(tail -n1 <<<"$out")"
  done
  local pct
  pct=$(df -P "$HOME" | awk 'NR == 2 { gsub("%", "", $5); print $5 }')
  rc=0; ((pct >= $(cfg_get monitor.disk_max_pct 90))) && rc=1
  _result disk "$rc" "storage ${pct}% full"
  local avail
  avail=$(mem_available_mb)
  rc=0; ((avail < $(cfg_get monitor.mem_min_mb 150))) && rc=1
  _result memory "$rc" "only ${avail} MB RAM available"
  local b t
  b=$(_battery)
  if [[ -n "$b" ]]; then
    read -r t _ _ <<<"$b"
    rc=0; ((t >= $(cfg_get monitor.battery_max_c 45))) && rc=1
    _result battery-temp "$rc" "battery at ${t}°C"
  fi
}

monitor_loop() {
  echo "$(date '+%F %T') monitor: started, every $(_interval)s"
  while :; do
    monitor_once || true
    sleep "$(_interval)"
  done
}

monitor_table() {
  local m rc out
  for m in $(modules_enabled); do
    rc=0; out=$(module_call "$m" health 2>&1) || rc=$?
    printf '%-14s %s %s\n' "$m" "$( ((rc == 0)) && echo ok || echo FAIL)" "$(tail -n1 <<<"$out")"
  done
  printf '%-14s %s MB available\n' memory "$(mem_available_mb)"
  printf '%-14s %s\n' battery "$(_battery || true)"
}

mod_cli() {
  case "${1:-}" in
    loop) monitor_loop ;;
    once) monitor_table ;;
    *) die "usage: rez monitor once|loop" ;;
  esac
}
