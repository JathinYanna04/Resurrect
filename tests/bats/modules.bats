#!/usr/bin/env bats
# Module contract and selection logic.

load test_helper

setup() {
  setup_sandbox
  load_libs
  detect_all
}

@test "every module in the order list exists and every file is in the list" {
  for m in "${REZ_MODULE_ORDER[@]}"; do [ -f "$REPO/modules/$m.sh" ]; done
  for f in "$REPO"/modules/*.sh; do
    m=$(basename "$f" .sh)
    [[ " ${REZ_MODULE_ORDER[*]} " == *" $m "* ]]
  done
}

@test "module contract: metadata and required functions" {
  for m in "${REZ_MODULE_ORDER[@]}"; do
    (
      module_load "$m"
      [ -n "$MOD_DESC" ] || { echo "$m: no MOD_DESC"; exit 1; }
      [[ "$MOD_ROOT" =~ ^(no|optional|required)$ ]] || { echo "$m: MOD_ROOT=$MOD_ROOT"; exit 1; }
      [ -n "$MOD_TESTED" ] || { echo "$m: no MOD_TESTED"; exit 1; }
      for fn in install status; do
        declare -F "mod_$fn" >/dev/null || { echo "$m: missing mod_$fn"; exit 1; }
      done
      if [ "$MOD_SERVICE" = 1 ]; then
        for fn in start stop health; do
          declare -F "mod_$fn" >/dev/null || { echo "$m: service without mod_$fn"; exit 1; }
        done
      fi
      for d in $MOD_DEPENDS; do [ -f "$REPO/modules/$d.sh" ] || { echo "$m: unknown dependency $d"; exit 1; }; done
    )
  done
}

@test "dependencies are added and order is stable" {
  run modules_sorted "vaultwarden,ntfy"
  [ "${lines[0]}" = base ]
  [ "${lines[1]}" = ntfy ]
  [ "${lines[2]}" = vaultwarden ]
}

@test "profiles only name real modules and all include base" {
  for p in lite standard full; do
    list=$(profile_modules "$p")
    csv_has "$list" base
    for m in ${list//,/ }; do [ -f "$REPO/modules/$m.sh" ]; done
  done
}

@test "lite profile stays under 200 MB estimated RAM" {
  total=0
  for m in $(profile_modules lite | tr , ' '); do total=$((total + $(module_meta "$m" RAM_EST_MB))); done
  [ "$total" -lt 200 ]
}

@test "jellyfin is refused on a 3 GB phone without an SD card" {
  run module_ineligible jellyfin
  [ "$status" -eq 0 ]
  [[ "$output" == *"needs 3500 MB RAM"* ]]
  [[ "$output" == *"SD card"* ]]
}

@test "jellyfin is offered with enough RAM and an SD card" {
  meminfo 7800000 4000000
  mkdir -p "$REZ_STORAGE_ROOT/1A2B-3C4D"
  detect_all
  run module_ineligible jellyfin
  [ "$status" -eq 1 ]
}

@test "root-only modules need root; optional ones do not" {
  REZ_HAS_ROOT=no run module_ineligible acc
  [[ "$output" == *"needs root"* ]]
  REZ_HAS_ROOT=no run module_ineligible adguard
  [ "$status" -eq 1 ]
  REZ_HAS_ROOT=yes run module_ineligible acc
  [ "$status" -eq 1 ]
}

@test "32-bit x86 cannot install modules without a build" {
  DEV_ARCH=386 run module_ineligible vaultwarden
  [[ "$output" == *"not available for 386"* ]]
}

@test "every pinned download has a checksum for each listed architecture" {
  source "$REPO/lib/versions.sh"
  for t in TAILSCALE NTFY FILEBROWSER ADGUARD VAULTWARDEN; do
    declare -n a="PIN_${t}_SHA256"
    [ "${#a[@]}" -ge 3 ]
    for k in "${!a[@]}"; do [[ "${a[$k]}" =~ ^[0-9a-f]{64}$ ]]; done
    unset -n a
  done
  [[ "$PIN_ACC_SHA256" =~ ^[0-9a-f]{64}$ ]]
  [[ "$PIN_COPYPARTY_SHA256" =~ ^[0-9a-f]{64}$ ]]
}

@test "fetch_verified refuses an empty checksum and a mismatch" {
  run fetch_verified "file://$REPO/LICENSE" "" "$T/x"
  [ "$status" -ne 0 ]
  printf 'hello' >"$T/src"
  run fetch_verified "file://$T/src" 0000000000000000000000000000000000000000000000000000000000000000 "$T/dst"
  [ "$status" -ne 0 ]
  [ ! -e "$T/dst" ]
  good=$(sha256sum "$T/src" | cut -d' ' -f1)
  fetch_verified "file://$T/src" "$good" "$T/dst"
  [ "$(cat "$T/dst")" = hello ]
}
