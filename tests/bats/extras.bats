#!/usr/bin/env bats
# extras/laptop/pull-backups.sh against a fake "phone" (a local directory
# reached through a fake ssh that runs commands locally).

load test_helper

setup() {
  setup_sandbox
  command -v rsync >/dev/null || skip "rsync not installed"
  PHONE=$T/phone
  mkdir -p "$PHONE/resurrect-backups" "$T/bin"
  # Fake ssh: drop options, ignore the host, run the command in $PHONE.
  cat >"$T/bin/fakessh" <<EOF
#!/usr/bin/env bash
while [[ "\$1" == -* ]]; do case "\$1" in -o|-p) shift 2 ;; *) shift ;; esac; done
shift  # host
cd "$PHONE" && exec bash -c "\$*"
EOF
  # Stub rez on the "phone".
  printf '#!/bin/sh\n[ "$1 $2" = "backup mark-pulled" ] && touch "%s/pulled"\n' "$PHONE" >"$T/bin/rez"
  chmod +x "$T/bin/fakessh" "$T/bin/rez"
  export PATH=$T/bin:$PATH REZ_SSH=$T/bin/fakessh
}

mkbackup() {
  local name=$1
  echo "data $name" | gzip >"$PHONE/resurrect-backups/$name"
  (cd "$PHONE/resurrect-backups" && sha256sum "$name" >"$name.sha256")
}

@test "pulls, verifies, marks the phone" {
  mkbackup resurrect-2026-01-01_0330.tar.gz
  run bash "$REPO/extras/laptop/pull-backups.sh" phone "$T/dest"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$T/dest/resurrect-2026-01-01_0330.tar.gz" ]
  [ -f "$PHONE/pulled" ]
  [ "$(stat -c %a "$T/dest")" = 700 ]
}

@test "keeps the newest N, never deletes because the phone did" {
  for d in 01 02 03 04; do mkbackup "resurrect-2026-01-${d}_0330.tar.gz"; done
  REZ_KEEP=3 bash "$REPO/extras/laptop/pull-backups.sh" phone "$T/dest"
  [ "$(ls "$T/dest"/*.tar.gz | wc -l)" -eq 3 ]
  [ ! -f "$T/dest/resurrect-2026-01-01_0330.tar.gz" ]
  # The phone loses everything: the computer's copies stay.
  rm -f "$PHONE"/resurrect-backups/*
  REZ_KEEP=3 bash "$REPO/extras/laptop/pull-backups.sh" phone "$T/dest"
  [ "$(ls "$T/dest"/*.tar.gz | wc -l)" -eq 3 ]
}

@test "a corrupted archive fails the pull" {
  mkbackup resurrect-2026-01-01_0330.tar.gz
  echo "0000000000000000000000000000000000000000000000000000000000000000  resurrect-2026-01-01_0330.tar.gz" \
    >"$PHONE/resurrect-backups/resurrect-2026-01-01_0330.tar.gz.sha256"
  run bash "$REPO/extras/laptop/pull-backups.sh" phone "$T/dest"
  [ "$status" -ne 0 ]
  [[ "$output" == *MISMATCH* ]]
  [ ! -f "$PHONE/pulled" ]
}

@test "unreachable phone is not an error" {
  printf '#!/bin/sh\nexit 255\n' >"$T/bin/fakessh"
  run bash "$REPO/extras/laptop/pull-backups.sh" phone "$T/dest"
  [ "$status" -eq 0 ]
  [[ "$output" == *unreachable* ]]
}
