# shellcheck shell=bash
# Module loader. A module is modules/<name>.sh defining metadata variables
# and mod_* functions (see docs/writing-a-module.md). Every action runs in a
# subshell so one module's functions never leak into the next.

[[ -n "${_REZ_MODULES_LOADED:-}" ]] && return 0
_REZ_MODULES_LOADED=1

# Install/start order. Dependencies come first.
REZ_MODULE_ORDER=(base tailscale cloudflared ntfy vaultwarden adguard copyparty filebrowser syncthing backup monitor alerts jellyfin acc)

module_file() { echo "$REZ_ROOT/modules/$1.sh"; }
module_exists() { [[ -f "$(module_file "$1")" ]]; }

_module_reset() {
  MOD_NAME='' MOD_DESC='' MOD_ROOT=no MOD_MIN_RAM_MB=0 MOD_NEEDS_EXTERNAL=0
  MOD_DEPENDS='' MOD_CONFLICTS='' MOD_PORTS='' MOD_ARCHES='arm64 armv7 amd64 386' MOD_RAM_EST_MB=0
  MOD_DISK_EST_MB=0 MOD_SERVICE=1 MOD_TESTED='no'
  unset -f mod_configure mod_install mod_start mod_stop mod_status mod_uninstall \
    mod_health mod_backup mod_restore_check mod_cron mod_info 2>/dev/null || true
}

# module_load NAME: source the module into the current shell.
module_load() {
  module_exists "$1" || die "unknown module: $1"
  _module_reset
  # shellcheck source=/dev/null
  source "$(module_file "$1")"
  [[ "$MOD_NAME" == "$1" ]] || die "modules/$1.sh sets MOD_NAME=$MOD_NAME"
}

# module_meta NAME VAR: one metadata value.
module_meta() ( module_load "$1"; v="MOD_$2"; printf '%s' "${!v}" )

# module_has NAME FUNC: does the module implement mod_FUNC?
module_has() ( module_load "$1"; declare -F "mod_$2" >/dev/null )

# module_call NAME FUNC [ARGS]: run mod_FUNC. Missing optional functions are
# a no-op. Anything that changes state runs in its own bash process so that
# `set -e` is always in force (see lib/module-call.sh). Read-only queries run
# in a cheaper subshell: `rez status` stays fast on old phones.
module_call() {
  local name=$1 fn=$2
  module_exists "$name" || die "unknown module: $name"
  case "$fn" in
    status | health | info | cron | doctor | restore_check)
      shift 2
      (
        module_load "$name"
        declare -F "mod_$fn" >/dev/null || exit 0
        "mod_$fn" "$@"
      )
      ;;
    *) bash "$REZ_ROOT/lib/module-call.sh" "$@" ;;
  esac
}

# module_ineligible NAME: print why NAME cannot be installed here; status 0
# if there is a reason, 1 if the module is fine.
module_ineligible() (
  module_load "$1"
  local why=()
  [[ "$MOD_ROOT" == required && "${REZ_HAS_ROOT:-no}" != yes ]] && why+=("needs root")
  if ((MOD_MIN_RAM_MB > 0 && ${DEV_MEM_TOTAL_MB:-0} < MOD_MIN_RAM_MB)); then
    why+=("needs ${MOD_MIN_RAM_MB} MB RAM (device has ${DEV_MEM_TOTAL_MB:-?})")
  fi
  if [[ "$MOD_NEEDS_EXTERNAL" == 1 && -z "${DEV_SD_PATH:-}" && -z "$(cfg_get media.path "")" ]]; then
    why+=("needs an SD card or external storage")
  fi
  [[ " $MOD_ARCHES " == *" ${DEV_ARCH:-arm64} "* ]] || why+=("not available for ${DEV_ARCH:-?}")
  ((${#why[@]})) || exit 1
  local out
  out=$(printf '%s; ' "${why[@]}")
  printf '%s' "${out%; }"
)

# modules_sorted LIST: LIST (comma separated) plus dependencies, in install order.
modules_sorted() {
  local want=",$1," m d changed=1
  for m in ${1//,/ }; do module_exists "$m" || die "unknown module: $m (see rez modules)"; done
  while ((changed)); do
    changed=0
    for m in "${REZ_MODULE_ORDER[@]}"; do
      [[ "$want" == *",$m,"* ]] || continue
      for d in $(module_meta "$m" DEPENDS); do
        if [[ "$want" != *",$d,"* ]]; then want+="$d,"; changed=1; fi
      done
    done
  done
  for m in "${REZ_MODULE_ORDER[@]}"; do
    [[ "$want" == *",$m,"* ]] && echo "$m"
  done
  return 0
}

# modules_enabled: installed modules in start order.
modules_enabled() {
  local m list
  list=$(cfg_get modules "")
  for m in "${REZ_MODULE_ORDER[@]}"; do
    csv_has "$list" "$m" && echo "$m"
  done
  return 0
}

profile_modules() {
  local f="$REZ_ROOT/profiles/$1.conf"
  [[ -r "$f" ]] || die "unknown profile: $1 (lite, standard, full)"
  awk -F= '$1 == "modules" { print $2 }' "$f"
}
