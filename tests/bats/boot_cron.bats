#!/usr/bin/env bats
# Startup and scheduled jobs.

load test_helper

setup() {
  setup_sandbox
  load_libs
}

@test "boot script: single file, full paths, points at this checkout" {
  boot_install_script
  [ -x "$REZ_BOOT_DIR/resurrect" ]
  [ "$(ls -A "$REZ_BOOT_DIR")" = resurrect ]
  grep -q "^exec $PREFIX/bin/bash $REPO/bin/rez boot$" "$REZ_BOOT_DIR/resurrect"
  head -1 "$REZ_BOOT_DIR/resurrect" | grep -q "^#!$PREFIX/bin/sh$"
}

@test "other boot files are moved aside (never deleted) when allowed" {
  mkdir -p "$REZ_BOOT_DIR"
  echo old >"$REZ_BOOT_DIR/start.sh"
  echo older >"$REZ_BOOT_DIR/start.sh.bak"
  cfg_set base.move_boot_files yes
  boot_install_script
  [ "$(ls -A "$REZ_BOOT_DIR")" = resurrect ]
  [ "$(cat "$HOME/.termux/boot-disabled/start.sh")" = old ]
  [ -f "$HOME/.termux/boot-disabled/start.sh.bak" ]
}

@test "other boot files are kept (with a warning) when not allowed" {
  mkdir -p "$REZ_BOOT_DIR"
  echo old >"$REZ_BOOT_DIR/start.sh"
  run boot_install_script
  [ -f "$REZ_BOOT_DIR/start.sh" ]
  [[ "$output" == *"will also run at boot"* ]]
}

@test "rez boot: a second concurrent copy exits immediately" {
  cfg_set modules ""
  mkdir -p "$REZ_STATE_DIR"
  # Hold the boot lock, then run rez boot.
  ( flock -n 9 && sleep 3 ) 9>"$REZ_STATE_DIR/boot.lock" 3>&- &
  holder=$!
  sleep 0.5
  rez boot
  grep -q "another copy is running" "$REZ_LOG_DIR/boot.log"
  wait "$holder"
}

@test "rez boot runs once and logs" {
  cfg_set modules ""
  rez boot
  grep -q "boot: done" "$REZ_LOG_DIR/boot.log"
  [ -f "$REZ_STATE_DIR/boot-time" ]
}

@test "cron block: user lines survive, block replaced, then removed" {
  printf '0 1 * * * my-own-job\n' | crontab -
  printf '30 3 * * * rez backup run\n' | cron_install_block
  printf '15 4 * * * rez other\n' | cron_install_block
  run crontab -l
  [[ "$output" == *"my-own-job"* ]]
  [[ "$output" == *"rez other"* ]]
  [[ "$output" != *"rez backup run"* ]]
  [ "$(grep -c '>>> resurrect' <<<"$output")" -eq 1 ]
  printf '' | cron_install_block
  run crontab -l
  [[ "$output" == *"my-own-job"* ]]
  [[ "$output" != *"resurrect"* ]]
}

@test "cron lines use full paths (cron has no useful PATH)" {
  run rez_cmd
  [ "$output" = "$PREFIX/bin/bash $REPO/bin/rez" ]
}

@test "base_sync_boot_and_cron collects module cron lines" {
  cfg_set modules base,backup
  base_sync_boot_and_cron
  run crontab -l
  [[ "$output" == *"backup run"* ]]
  [[ "$output" == *"backup verify"* ]]
  [ -x "$REZ_BOOT_DIR/resurrect" ]
}
