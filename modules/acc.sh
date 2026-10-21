# shellcheck shell=bash
# acc: battery charge limit with ACC (Advanced Charging Controller). ROOT ONLY.
#
# A phone plugged in 24/7 at 100 % swells and ages fast. ACC pauses
# charging at a limit (default 80 %) and resumes below another (70 %).
#
# ACC is a Magisk module. rez downloads the pinned, checksum-verified zip
# and, only after you confirm, asks Magisk to install it. It never reboots
# for you: reboot yourself when convenient, then run_cmd `rez acc apply`.

MOD_NAME=acc
MOD_DESC="ACC battery charge limit (stop at 80 %, resume at 70 %)"
MOD_ROOT=required
MOD_DEPENDS="base"
MOD_SERVICE=0
MOD_DISK_EST_MB=1
MOD_TESTED="no (needs root; command sequence matches a working manual setup)"

_pause() { cfg_get acc.pause 80; }
_resume() { cfg_get acc.resume 70; }
_acc() { as_root "acc $*"; }
_installed() { as_root "command -v acc" >/dev/null 2>&1; }

mod_configure() {
  local p r
  p=$(cfg_get acc.pause "$(ui_input "Charge limit" "Stop charging at (%)" 80)")
  r=$(cfg_get acc.resume "$(ui_input "Charge limit" "Resume charging below (%)" 70)")
  if ! [[ "$p" =~ ^[0-9]+$ && "$r" =~ ^[0-9]+$ ]] || ! ((r < p && p <= 100 && r >= 20)); then
    die "invalid limits: stop $p, resume $r (need 20 <= resume < stop <= 100)"
  fi
  cfg_set acc.pause "$p"
  cfg_set acc.resume "$r"
}

mod_install() {
  [[ "$REZ_HAS_ROOT" == yes ]] || die "acc needs root"
  if _installed; then ok "ACC already installed"; acc_apply; return 0; fi
  local zip="$REZ_CACHE_DIR/acc-$PIN_ACC_VERSION.zip"
  fetch_verified "$PIN_ACC_URL" "$PIN_ACC_SHA256" "$zip"
  ui_yesno "Install ACC" "This installs the ACC Magisk module ($PIN_ACC_VERSION, checksum verified):
  $zip

It changes how the phone charges (that is the point). A reboot is needed
afterwards; resurrect will NOT reboot for you.

Install it now?" no || { info "skipped. Install the zip yourself from the Magisk app if you prefer."; return 0; }
  as_root "magisk --install-module '$zip'" || die "Magisk could not install the module. Install $zip from the Magisk app instead."
  cfg_set acc.pending_reboot yes
  ui_msg "Reboot needed" "ACC is installed. Reboot when convenient, then run: rez acc apply"
}

acc_apply() {
  _installed || { warn "ACC is not active yet (reboot pending?)"; return 1; }
  _acc "-s pause_capacity=$(_pause) resume_capacity=$(_resume)" >/dev/null
  cfg_unset acc.pending_reboot
  ok "charge limit set: pause at $(_pause) %, resume below $(_resume) %"
}

_battery() { cat /sys/class/power_supply/battery/capacity 2>/dev/null || as_root "cat /sys/class/power_supply/battery/capacity"; }
_charging() { local s; s=$(cat /sys/class/power_supply/battery/status 2>/dev/null || as_root "cat /sys/class/power_supply/battery/status"); [[ "$s" == Charging ]]; }

mod_status() {
  local st
  st="limits $(_pause)/$(_resume) %, battery $(_battery) %"
  [[ "$(cfg_get acc.pending_reboot no)" == yes ]] && st+=", REBOOT PENDING"
  _installed || st+=", ACC NOT ACTIVE"
  printf '%-14s %s\n' acc "$st"
}

# Charging above the limit = cap broken. Not charging far below = stuck.
mod_health() {
  [[ "$(cfg_get acc.pending_reboot no)" == yes ]] && return 0
  local cap
  cap=$(_battery) || return 0
  if ((cap > $(_pause) + 5)) && _charging; then echo "charging at ${cap}% despite the $(_pause)% limit"; return 1; fi
  if ((cap < $(_resume) - 3)) && ! _charging; then echo "not charging at ${cap}% (resume is $(_resume)%); charger unplugged?"; return 1; fi
  return 0
}

mod_uninstall() {
  _installed && ui_yesno "ACC" "Uninstall the ACC module? Charging returns to normal (100 %)." no && as_root "acc --uninstall"
  return 0
}

mod_info() { printf 'Charging:   ACC pause %s %%, resume %s %% (rez acc status)\n' "$(_pause)" "$(_resume)"; }

mod_cli() {
  case "${1:-}" in
    apply) acc_apply ;;
    set) cfg_set acc.pause "${2:?usage: rez acc set STOP RESUME}"; cfg_set acc.resume "${3:?usage: rez acc set STOP RESUME}"; mod_configure; acc_apply ;;
    status) mod_status; _acc -i 2>/dev/null | head -20 || true ;;
    *) die "usage: rez acc apply|set STOP RESUME|status" ;;
  esac
}
