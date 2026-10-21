# shellcheck shell=bash
# `rez doctor`: check the rules that keep a phone homelab alive.

[[ -n "${_REZ_DOCTOR_LOADED:-}" ]] && return 0
_REZ_DOCTOR_LOADED=1

_doc_fail=0 _doc_warn=0
_d_ok()   { [[ "$_doc_quiet" == 1 ]] || printf '  %sPASS%s %s\n' "$_c_grn" "$_c_off" "$*"; }
_d_warn() { printf '  %sWARN%s %s\n' "$_c_ylw" "$_c_off" "$*"; _doc_warn=$((_doc_warn + 1)); }
_d_fail() { printf '  %sFAIL%s %s\n' "$_c_red" "$_c_off" "$*"; _doc_fail=$((_doc_fail + 1)); }

doctor_main() {
  _doc_quiet=0
  [[ "${1:-}" == --quiet ]] && _doc_quiet=1
  detect_all
  echo "Termux"
  if [[ "$DEV_TERMUX_SOURCE" == GOOGLE_PLAY_STORE ]]; then
    _d_fail "Termux is the outdated Google Play build: reinstall from F-Droid or GitHub"
  else
    _d_ok "Termux $DEV_TERMUX_VERSION ($DEV_TERMUX_SOURCE)"
  fi
  case "$DEV_TERMUX_BOOT" in
    yes) _d_ok "Termux:Boot installed (open it once after installing, or it never runs)" ;;
    no) _d_fail "Termux:Boot not installed: nothing will start after a reboot" ;;
    *) _d_warn "could not check for Termux:Boot (pm list packages failed)" ;;
  esac

  echo "Startup"
  local bootf="$REZ_BOOT_DIR/resurrect"
  if [[ -x "$bootf" ]]; then _d_ok "boot script present"
  elif csv_has "$(cfg_get modules "")" base; then _d_fail "boot script missing: run rez cron sync"
  fi
  if [[ -n "$DEV_BOOT_EXTRA" ]]; then
    _d_fail "other files in ~/.termux/boot also run at boot: $DEV_BOOT_EXTRA (move them to ~/.termux/boot-disabled/)"
  else
    _d_ok "nothing else in ~/.termux/boot"
  fi

  echo "Android background limits"
  case "$DEV_PHANTOM" in
    n/a) _d_ok "Android $DEV_ANDROID has no phantom process killer" ;;
    disabled) _d_ok "phantom process killer disabled" ;;
    *)
      _d_warn "Android $DEV_ANDROID may kill Termux's background processes. Fix (once, from a computer with adb):
         adb shell \"/system/bin/device_config set_sync_disabled_for_tests persistent\"
         adb shell \"/system/bin/device_config put activity_manager max_phantom_processes 2147483647\"
         adb shell settings put global settings_enable_monitor_phantom_procs false
       On Android 14+ you can instead enable Developer options > \"Disable child process restrictions\"."
      ;;
  esac
  _d_warn "cannot verify battery optimization from Termux: make sure Settings > Apps > Termux > Battery is \"Unrestricted\""

  echo "Resources"
  local avail total free
  avail=$(mem_available_mb); total=$(mem_total_mb); free=$(free_mb "$HOME")
  if ((avail < 300)); then _d_fail "MemAvailable ${avail} MB of ${total} MB: stop or remove modules"
  elif ((avail < 600)); then _d_warn "MemAvailable ${avail} MB of ${total} MB is getting low"
  else _d_ok "MemAvailable ${avail} MB of ${total} MB"
  fi
  if ((free < 1024)); then _d_fail "only ${free} MB free storage"
  else _d_ok "${free} MB free storage"
  fi

  echo "Services"
  local m
  for m in $(modules_enabled); do
    if module_call "$m" health >/dev/null 2>&1; then _d_ok "$m healthy"
    elif [[ "$(cfg_get "$m.autostart" yes)" == no ]]; then _d_ok "$m installed (not started automatically)"
    else _d_fail "$m unhealthy: rez status / rez logs $m"
    fi
    module_call "$m" doctor 2>/dev/null || true
  done
  if csv_has "$(cfg_get modules "")" base && have crontab; then
    if crontab -l 2>/dev/null | grep -qF "$REZ_CRON_BEGIN"; then _d_ok "scheduled jobs installed"
    else _d_warn "no resurrect block in crontab: run rez cron sync"
    fi
  fi

  echo
  if ((_doc_fail)); then printf '%d problem(s), %d warning(s)\n' "$_doc_fail" "$_doc_warn"; return 1; fi
  printf 'no problems, %d warning(s)\n' "$_doc_warn"
}
