#!/usr/bin/env bats

load test_helper

setup() {
  setup_sandbox
  load_libs
}

@test "cfg_get returns the default when unset" {
  run cfg_get nope.key fallback
  [ "$output" = fallback ]
}

@test "cfg_set then cfg_get, values may contain = and spaces" {
  cfg_set a.b "x = y z"
  run cfg_get a.b
  [ "$output" = "x = y z" ]
}

@test "cfg_set replaces in place and keeps comments and order" {
  printf '# hello\nfirst=1\nsecond=2\n' >"$REZ_CONFIG_FILE"
  cfg_set first 9
  run cat "$REZ_CONFIG_FILE"
  [ "${lines[0]}" = "# hello" ]
  [ "${lines[1]}" = "first=9" ]
  [ "${lines[2]}" = "second=2" ]
}

@test "config file is mode 600" {
  cfg_set k v
  [ "$(stat -c %a "$REZ_CONFIG_FILE")" = 600 ]
}

@test "cfg_get ignores commented keys and the file is never executed" {
  printf '#k=commented\nk=$(touch %s/pwned)\n' "$T" >"$REZ_CONFIG_FILE"
  run cfg_get k
  [ "$output" = "\$(touch $T/pwned)" ]
  [ ! -e "$T/pwned" ]
}

@test "environment override REZ_CFG_*" {
  cfg_set ntfy.port 2586
  REZ_CFG_ntfy_port=9999 run cfg_get ntfy.port
  [ "$output" = 9999 ]
}

@test "invalid keys and newlines are rejected" {
  run cfg_set 'bad key' v
  [ "$status" -ne 0 ]
  run cfg_set good $'two\nlines'
  [ "$status" -ne 0 ]
}

@test "cfg_import merges a file, skipping junk" {
  printf '# answers\nprofile = lite\n\nnot a pair\nbase.ssh_pubkey_file=~/k.pub\n' >"$T/a.conf"
  cfg_import "$T/a.conf"
  [ "$(cfg_get profile)" = lite ]
  [ "$(cfg_get base.ssh_pubkey_file)" = "~/k.pub" ]
}

@test "cfg_list_add / cfg_list_del" {
  cfg_list_add modules base
  cfg_list_add modules ntfy
  cfg_list_add modules base
  [ "$(cfg_get modules)" = "base,ntfy" ]
  cfg_list_del modules base
  [ "$(cfg_get modules)" = "ntfy" ]
}

@test "secrets: 600 files, generated once, names validated" {
  a=$(secret_ensure test_secret 24)
  b=$(secret_ensure test_secret 24)
  [ "$a" = "$b" ]
  [ "${#a}" -eq 24 ]
  [ "$(stat -c %a "$REZ_CONFIG_DIR/secrets/test_secret")" = 600 ]
  run secret_get '../escape'
  [ "$status" -ne 0 ]
}

@test "dry-run sandbox: answers visible, real file untouched" {
  cfg_set keep me
  REZ_DRY_RUN=1
  cfg_sandbox
  cfg_set new value 2>/dev/null
  [ "$(cfg_get new)" = value ]
  [ "$(cfg_get keep)" = me ]
  run grep -c new "$HOME/.config/resurrect/resurrect.conf"
  [ "$output" = 0 ]
}

@test "service_bind: localhost with built-in tailscale, all interfaces otherwise" {
  cfg_set tailscale.mode proot
  [ "$(service_bind)" = 127.0.0.1 ]
  cfg_set tailscale.mode app
  [ "$(service_bind)" = 0.0.0.0 ]
  cfg_set net.bind 192.0.2.10
  [ "$(service_bind)" = 192.0.2.10 ]
}
