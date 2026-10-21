# shellcheck shell=bash
# Device detection. Read-only: nothing here changes the device.
# Results land in DEV_* variables; detect_all fills them all.

[[ -n "${_REZ_DETECT_LOADED:-}" ]] && return 0
_REZ_DETECT_LOADED=1

: "${REZ_GETPROP:=getprop}"
: "${REZ_STORAGE_ROOT:=/storage}"

prop() { "$REZ_GETPROP" "$1" 2>/dev/null | tr -d '\r'; }

detect_android() {
  DEV_ANDROID=$(prop ro.build.version.release)
  DEV_SDK=$(prop ro.build.version.sdk)
  DEV_MANUFACTURER=$(prop ro.product.manufacturer)
  DEV_MODEL=$(prop ro.product.model)
  DEV_CODENAME=$(prop ro.product.device)
  [[ -n "$DEV_CODENAME" ]] || DEV_CODENAME=$(prop ro.build.product)
  DEV_ROM=$(prop ro.lineage.version)
  [[ -n "$DEV_ROM" ]] && DEV_ROM="LineageOS $DEV_ROM"
  [[ -n "$DEV_ROM" ]] || DEV_ROM=$(prop ro.modversion)
  [[ -n "$DEV_ROM" ]] || DEV_ROM="stock ($(prop ro.build.display.id))"
  DEV_SECURITY_PATCH=$(prop ro.build.version.security_patch)
  : "${DEV_ANDROID:=unknown}" "${DEV_SDK:=0}"
}

detect_arch() {
  DEV_UNAME_M=$(uname -m)
  DEV_ARCH=$(go_arch "$DEV_UNAME_M")
}

detect_memory() {
  DEV_MEM_TOTAL_MB=$(mem_total_mb)
  DEV_MEM_AVAIL_MB=$(mem_available_mb)
}

detect_storage() {
  DEV_FREE_HOME_MB=$(free_mb "$HOME")
  DEV_FREE_HOME_MB=${DEV_FREE_HOME_MB:-0}
  # Removable storage shows up as /storage/XXXX-XXXX. Reading it needs
  # termux-setup-storage; writing outside Android/data/com.termux is
  # blocked on Android 11+ without root, so we report both.
  DEV_SD_PATH='' DEV_SD_FREE_MB=0 DEV_SD_WRITABLE_PATH=''
  local d
  for d in "$REZ_STORAGE_ROOT"/*; do
    [[ -d "$d" ]] || continue
    case "${d##*/}" in emulated | self) continue ;; esac
    [[ "${d##*/}" =~ ^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$ ]] || continue
    DEV_SD_PATH=$d
    DEV_SD_FREE_MB=$(free_mb "$d")
    if [[ -d "$d/Android/data/com.termux" && -w "$d/Android/data/com.termux" ]]; then
      DEV_SD_WRITABLE_PATH="$d/Android/data/com.termux/files"
    fi
    break
  done
}

# detect_root [ask]: without "ask" only checks whether su exists (no prompt).
# With "ask", runs `su -c id -u` with a timeout, which makes Magisk show its
# grant dialog. Sets DEV_ROOT to none | available | denied and REZ_HAS_ROOT.
detect_root() {
  DEV_ROOT=none DEV_ROOT_KIND=''
  if ! have su; then REZ_HAS_ROOT=no; return 0; fi
  DEV_ROOT=available
  if su -v 2>/dev/null | grep -qi magisk; then DEV_ROOT_KIND=Magisk
  elif su -v 2>/dev/null | grep -qi kernelsu; then DEV_ROOT_KIND=KernelSU
  fi
  if [[ "${1:-}" == ask ]]; then
    if [[ "$(timeout 30 su -c 'id -u' 2>/dev/null </dev/null)" == 0 ]]; then
      REZ_HAS_ROOT=yes
    else
      DEV_ROOT=denied REZ_HAS_ROOT=no
    fi
  fi
}

detect_termux() {
  # TERMUX_APK_RELEASE is set by Termux 0.118+: F_DROID, GITHUB or GOOGLE_PLAY_STORE.
  DEV_TERMUX_VERSION=${TERMUX_VERSION:-unknown}
  DEV_TERMUX_SOURCE=${TERMUX_APK_RELEASE:-unknown}
  DEV_TERMUX_BOOT=unknown DEV_TERMUX_API=unknown
  local pkgs
  if pkgs=$(timeout 20 pm list packages 2>/dev/null); then
    grep -q 'package:com.termux.boot$' <<<"$pkgs" && DEV_TERMUX_BOOT=yes || DEV_TERMUX_BOOT=no
    grep -q 'package:com.termux.api$' <<<"$pkgs" && DEV_TERMUX_API=yes || DEV_TERMUX_API=no
  fi
  DEV_BOOT_EXTRA=''
  if [[ -d "$REZ_BOOT_DIR" ]]; then
    local f
    for f in "$REZ_BOOT_DIR"/* "$REZ_BOOT_DIR"/.[!.]*; do
      [[ -e "$f" ]] || continue
      [[ "${f##*/}" == resurrect ]] && continue
      DEV_BOOT_EXTRA+="${f##*/} "
    done
  fi
}

# Android 12+ kills "phantom" child processes of apps once there are more
# than 32 of them, and kills runaway CPU users. Long-running Termux servers
# die at random without the fix.
detect_phantom() {
  DEV_PHANTOM=n/a
  ((DEV_SDK >= 31)) || return 0
  DEV_PHANTOM=unknown
  local v
  v=$(timeout 10 settings get global settings_enable_monitor_phantom_procs 2>/dev/null) || return 0
  case "$v" in
    false) DEV_PHANTOM=disabled ;;
    true | null | '') DEV_PHANTOM=active ;;
  esac
}

detect_all() {
  detect_android
  detect_arch
  detect_memory
  detect_storage
  detect_root "${1:-}"
  detect_termux
  detect_phantom
}

# recommend_profile: by MemTotal. Phones report less than their marketing
# size (a "3 GB" device shows ~2.7-2.9 GB), hence the odd thresholds.
recommend_profile() {
  local mt=${1:-$DEV_MEM_TOTAL_MB}
  if ((mt < 2600)); then echo lite
  elif ((mt < 5200)); then echo standard
  else echo full
  fi
}

# detect_report: plain text, safe to paste into a GitHub issue (no serials,
# no IDs, no network addresses).
detect_report() {
  cat <<EOF
resurrect $REZ_VERSION device report
Device:      $DEV_MANUFACTURER $DEV_MODEL (codename: $DEV_CODENAME)
Android:     $DEV_ANDROID (SDK $DEV_SDK), patch $DEV_SECURITY_PATCH
ROM:         $DEV_ROM
Arch:        $DEV_UNAME_M ($DEV_ARCH)
RAM:         total ${DEV_MEM_TOTAL_MB} MB, available ${DEV_MEM_AVAIL_MB} MB
Storage:     ${DEV_FREE_HOME_MB} MB free in Termux home
SD card:     ${DEV_SD_PATH:+present, ${DEV_SD_FREE_MB} MB free}${DEV_SD_PATH:-none detected}${DEV_SD_WRITABLE_PATH:+ (Termux folder writable)}
Root:        $DEV_ROOT${DEV_ROOT_KIND:+ ($DEV_ROOT_KIND)}
Termux:      $DEV_TERMUX_VERSION from $DEV_TERMUX_SOURCE; Termux:Boot $DEV_TERMUX_BOOT; Termux:API $DEV_TERMUX_API
Phantom process killer: $DEV_PHANTOM
Profile:     $(recommend_profile) recommended
EOF
}
