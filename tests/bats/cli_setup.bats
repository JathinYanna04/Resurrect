#!/usr/bin/env bats
# End-to-end CLI behaviour in dry-run mode (nothing is installed).

load test_helper

setup() {
  setup_sandbox
}

@test "rez --version and help" {
  run rez --version
  [[ "$output" == "resurrect "* ]]
  run rez help
  [[ "$output" == *"Usage: rez"* ]]
}

@test "unknown command fails with usage" {
  run rez frobnicate
  [ "$status" -eq 2 ]
}

@test "setup refuses to run outside Termux unless allowed" {
  [[ -d /data/data/com.termux/files/usr ]] && skip "this machine is Termux"
  REZ_ALLOW_NON_TERMUX=0 run rez --yes setup --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"inside Termux"* ]]
}

@test "dry-run setup works for every profile and changes nothing" {
  for p in lite standard full; do
    run rez --dry-run --yes setup --profile "$p"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
  done
  [ ! -e "$REZ_CONFIG_FILE" ]
  [ ! -e "$REZ_BOOT_DIR/resurrect" ]
  [ ! -e "$HOME/.crontab" ]
}

@test "--modules installs exactly those plus dependencies" {
  run rez --dry-run --yes setup --modules vaultwarden
  [ "$status" -eq 0 ]
  [[ "$output" == *"Modules: base vaultwarden"* ]]
}

@test "ineligible modules are skipped with a reason" {
  run rez --dry-run --yes setup --modules base,jellyfin,acc
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping jellyfin"* ]]
  [[ "$output" == *"skipping acc: needs root"* ]]
}

@test "unknown profile and module are errors" {
  run rez --dry-run --yes setup --profile huge
  [ "$status" -ne 0 ]
  run rez --dry-run --yes setup --modules base,nosuchthing
  [ "$status" -ne 0 ]
}

@test "--config answers are used (vaultwarden picks the tailscale cert)" {
  printf 'tailscale.mode=proot\nvaultwarden.port=8443\n' >"$T/a.conf"
  run rez --dry-run --yes setup --modules tailscale,vaultwarden --config "$T/a.conf"
  [[ "$output" == *"set vaultwarden.https=tailscale"* ]]
}

@test "vaultwarden falls back to self-signed when tailscale is not installed" {
  printf 'tailscale.mode=proot\n' >"$T/a.conf"
  run rez --dry-run --yes setup --modules vaultwarden --config "$T/a.conf"
  [[ "$output" == *"set vaultwarden.https=selfsigned"* ]]
}

@test "rez install asks the module's questions first" {
  run rez --dry-run --yes install backup
  [[ "$output" == *"set backup.keep=7"* ]]
}

@test "rez device never touches fastboot or flashing tools" {
  printf '#!/bin/sh\necho CALLED >> %s/forbidden\n' "$T" >"$PREFIX/bin/fastboot"
  cp "$PREFIX/bin/fastboot" "$PREFIX/bin/adb"
  chmod +x "$PREFIX/bin/fastboot" "$PREFIX/bin/adb"
  run rez device
  [ "$status" -eq 0 ]
  [[ "$output" == *"wiki.lineageos.org/devices/exampletab"* ]]
  [[ "$output" == *"ERASES ALL DATA"* ]]
  [ ! -e "$T/forbidden" ]
}

@test "rez modules lists all modules with eligibility" {
  run rez modules
  [ "$status" -eq 0 ]
  [[ "$output" == *"jellyfin     n/a"* ]]
  [[ "$output" == *"vaultwarden  available"* ]]
}

@test "doctor reports extra boot files as a failure" {
  mkdir -p "$REZ_BOOT_DIR"
  touch "$REZ_BOOT_DIR/old.sh"
  run rez doctor
  [[ "$output" == *"FAIL other files in ~/.termux/boot"* ]]
}

@test "doctor explains the phantom process killer on Android 12+" {
  MOCK_ro_build_version_sdk=33 MOCK_ro_build_version_release=13 run rez doctor
  [[ "$output" == *"max_phantom_processes"* ]]
}

@test "rez alerts run JOB --dry-run passes --dry-run to the job" {
  # bin/rez parses --dry-run as a global option; the job must still get it,
  # or a "test" run calls the LLM, sends alerts and marks items as seen.
  mkdir -p "$REZ_CONFIG_DIR/alerts" "$T/bin"
  touch "$REZ_CONFIG_DIR/alerts/demo.toml"
  printf '#!/bin/sh\necho "python3 $*"\n' >"$T/bin/python3"
  chmod +x "$T/bin/python3"
  PATH=$T/bin:$PATH run rez alerts run demo --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"demo.toml --dry-run"* ]]
}
