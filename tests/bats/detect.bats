#!/usr/bin/env bats

load test_helper

setup() {
  setup_sandbox
  load_libs
}

@test "memory comes from MemTotal/MemAvailable, not free" {
  meminfo 2878000 1440000
  detect_memory
  [ "$DEV_MEM_TOTAL_MB" -eq 2810 ]
  [ "$DEV_MEM_AVAIL_MB" -eq 1406 ]
}

@test "MemFree is the fallback on kernels without MemAvailable" {
  printf 'MemTotal: 2000000 kB\nMemFree: 512000 kB\n' >"$REZ_PROC/meminfo"
  [ "$(mem_available_mb)" -eq 500 ]
}

@test "profile thresholds follow real-world MemTotal of 2/3/4/6/8 GB phones" {
  [ "$(recommend_profile 1850)" = lite ]      # 2 GB phone
  [ "$(recommend_profile 2810)" = standard ]  # 3 GB phone
  [ "$(recommend_profile 3700)" = standard ]  # 4 GB phone
  [ "$(recommend_profile 5600)" = full ]      # 6 GB phone
  [ "$(recommend_profile 7600)" = full ]      # 8 GB phone
}

@test "android properties from getprop" {
  detect_android
  [ "$DEV_ANDROID" = 11 ]
  [ "$DEV_SDK" = 30 ]
  [ "$DEV_CODENAME" = exampletab ]
  [[ "$DEV_ROM" == stock* ]]
}

@test "LineageOS is recognised" {
  MOCK_ro_lineage_version=21.0-20240101-NIGHTLY-exampletab detect_android
  [[ "$DEV_ROM" == "LineageOS 21.0"* ]]
}

@test "architecture mapping" {
  [ "$(go_arch aarch64)" = arm64 ]
  [ "$(go_arch armv8l)" = armv7 ]
  [ "$(go_arch armv7l)" = armv7 ]
  [ "$(go_arch x86_64)" = amd64 ]
  [ "$(go_arch i686)" = 386 ]
  [ "$(go_arch mips)" = unknown ]
}

@test "SD card: XXXX-XXXX volumes only, writable Termux folder detected" {
  mkdir -p "$REZ_STORAGE_ROOT/emulated/0" "$REZ_STORAGE_ROOT/self" "$REZ_STORAGE_ROOT/1A2B-3C4D/Android/data/com.termux"
  detect_storage
  [ "$DEV_SD_PATH" = "$REZ_STORAGE_ROOT/1A2B-3C4D" ]
  [ "$DEV_SD_WRITABLE_PATH" = "$REZ_STORAGE_ROOT/1A2B-3C4D/Android/data/com.termux/files" ]
}

@test "no SD card" {
  mkdir -p "$REZ_STORAGE_ROOT/emulated/0"
  detect_storage
  [ -z "$DEV_SD_PATH" ]
}

@test "phantom process killer only matters from Android 12 (SDK 31)" {
  DEV_SDK=30 detect_phantom
  [ "$DEV_PHANTOM" = n/a ]
  DEV_SDK=34
  detect_phantom
  [ "$DEV_PHANTOM" != n/a ]
}

@test "root check never prompts unless asked" {
  # A fake su that records every call.
  printf '#!/bin/sh\necho "$*" >> "%s/su.log"\n[ "$1" = -v ] && echo 27.0:MAGISK && exit 0\necho 0\n' "$T" >"$PREFIX/bin/su"
  chmod +x "$PREFIX/bin/su"
  detect_root
  [ "$DEV_ROOT" = available ]
  [ "$DEV_ROOT_KIND" = Magisk ]
  ! grep -q 'id -u' "$T/su.log"
  detect_root ask
  [ "$REZ_HAS_ROOT" = yes ]
  grep -q 'id -u' "$T/su.log"
}

@test "Termux:Boot extras are listed" {
  mkdir -p "$REZ_BOOT_DIR"
  touch "$REZ_BOOT_DIR/resurrect" "$REZ_BOOT_DIR/start.sh" "$REZ_BOOT_DIR/start.sh.bak"
  detect_termux
  [[ "$DEV_BOOT_EXTRA" == *start.sh* ]]
  [[ "$DEV_BOOT_EXTRA" == *start.sh.bak* ]]
  [[ "$DEV_BOOT_EXTRA" != *resurrect* ]]
}

@test "device report is safe to share: no serial or addresses" {
  export MOCK_ro_serialno=SERIAL123456  # fake, on purpose  privacy-scan: allow
  detect_all
  run detect_report
  [[ "$output" != *SERIAL123456* ]]
  [[ "$output" == *"codename: exampletab"* ]]
}

@test "bootloader state from read-only properties" {
  run bootloader_state
  [ "$output" = unlocked ]
  MOCK_ro_boot_flash_locked=1 run bootloader_state
  [ "$output" = locked ]
}
