# shellcheck shell=bash
# Configuration: one key=value file, parsed (never sourced), plus a secrets
# directory with one file per secret (mode 600).
#
#   ~/.config/resurrect/resurrect.conf     settings (safe to show)
#   ~/.config/resurrect/secrets/<name>     secrets (never printed, never logged)

[[ -n "${_REZ_CONFIG_LOADED:-}" ]] && return 0
_REZ_CONFIG_LOADED=1

: "${REZ_CONFIG_FILE:=$REZ_CONFIG_DIR/resurrect.conf}"

# cfg_sandbox: in dry-run mode, point REZ_CONFIG_FILE at a scratch copy so
# answers given during the run are visible to later steps while the real
# file stays untouched.
cfg_sandbox() {
  [[ "$REZ_DRY_RUN" == 1 ]] || return 0
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/rez-dry-conf.XXXXXX")
  [[ -r "$REZ_CONFIG_FILE" ]] && cat "$REZ_CONFIG_FILE" >"$tmp"
  REZ_CONFIG_FILE=$tmp
  export REZ_CONFIG_FILE
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" EXIT
}

_cfg_valid_key() { [[ "$1" =~ ^[a-z0-9_.-]+$ ]]; }

# cfg_get KEY [DEFAULT]: value of KEY from $REZ_CONFIG_FILE (last one wins).
# Environment overrides: REZ_CFG_<KEY with . and - as _> (used by tests and CI).
cfg_get() {
  local key=$1 def=${2-} envk val
  envk="REZ_CFG_${key//[.-]/_}"
  if [[ -n "${!envk+x}" ]]; then printf '%s' "${!envk}"; return 0; fi
  if [[ -r "$REZ_CONFIG_FILE" ]]; then
    val=$(awk -v k="$key" '
      /^[[:space:]]*#/ { next }
      { i = index($0, "="); if (i == 0) next
        kk = substr($0, 1, i - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", kk)
        if (kk == k) { v = substr($0, i + 1); found = 1 } }
      END { if (found) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); print v } else exit 1 }' "$REZ_CONFIG_FILE") \
      && { printf '%s' "$val"; return 0; }
  fi
  printf '%s' "$def"
}

# cfg_set KEY VALUE: create or replace KEY, keeping comments and order.
cfg_set() {
  local key=$1 val=$2
  _cfg_valid_key "$key" || die "invalid config key: $key"
  [[ "$val" == *$'\n'* ]] && die "config values cannot contain newlines ($key)"
  [[ "$REZ_DRY_RUN" == 1 ]] && printf '[dry-run] set %s=%s\n' "$key" "$val" >&2
  mkdir -p "$(dirname "$REZ_CONFIG_FILE")"
  touch "$REZ_CONFIG_FILE"
  awk -v k="$key" -v v="$val" '
    BEGIN { done = 0 }
    { i = index($0, "=")
      if (i > 0 && $0 !~ /^[[:space:]]*#/) {
        kk = substr($0, 1, i - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", kk)
        if (kk == k) { if (!done) print k "=" v; done = 1; next }
      }
      print }
    END { if (!done) print k "=" v }' "$REZ_CONFIG_FILE" | REZ_DRY_RUN=0 atomic_write "$REZ_CONFIG_FILE" 600
}

cfg_unset() {
  local key=$1
  [[ -r "$REZ_CONFIG_FILE" ]] || return 0
  awk -v k="$key" '{ i = index($0, "="); kk = substr($0, 1, i - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", kk)
    if (i > 0 && kk == k && $0 !~ /^[[:space:]]*#/) next; print }' "$REZ_CONFIG_FILE" | REZ_DRY_RUN=0 atomic_write "$REZ_CONFIG_FILE" 600
}

# cfg_import FILE: merge every key=value from FILE (used by --config).
cfg_import() {
  local file=$1 line key val
  [[ -r "$file" ]] || die "config file not readable: $file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" == *=* ]] || { warn "ignoring line without '=' in $file: $line"; continue; }
    key=${line%%=*}; val=${line#*=}
    key=${key//[[:space:]]/}
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
    _cfg_valid_key "$key" || { warn "ignoring invalid key in $file: $key"; continue; }
    cfg_set "$key" "$val"
  done <"$file"
}

# cfg_list_add KEY ITEM / cfg_list_del KEY ITEM: comma-separated sets.
cfg_list_add() {
  local cur
  cur=$(cfg_get "$1" "")
  csv_has "$cur" "$2" && return 0
  cfg_set "$1" "${cur:+$cur,}$2"
}

cfg_list_del() {
  local cur out='' x
  cur=$(cfg_get "$1" "")
  IFS=',' read -ra _items <<<"$cur"
  for x in "${_items[@]}"; do
    [[ -n "$x" && "$x" != "$2" ]] && out+="${out:+,}$x"
  done
  cfg_set "$1" "$out"
}

# --- Secrets -----------------------------------------------------------------
_secret_path() {
  [[ "$1" =~ ^[a-z0-9_]+$ ]] || die "invalid secret name: $1"
  echo "$REZ_CONFIG_DIR/secrets/$1"
}

secret_get() {
  local f
  f=$(_secret_path "$1")
  [[ -r "$f" ]] || return 1
  cat "$f"
}

secret_set() {
  local f
  f=$(_secret_path "$1")
  mkdir -p "$(dirname "$f")"
  chmod 700 "$(dirname "$f")"
  printf '%s' "$2" | atomic_write "$f" 600
}

secret_del() { run_cmd rm -f "$(_secret_path "$1")"; }

# secret_ensure NAME [LEN]: print the secret, generating it on first use.
secret_ensure() {
  local v
  if v=$(secret_get "$1"); then printf '%s' "$v"; return 0; fi
  v=$(rand_token "${2:-32}")
  secret_set "$1" "$v"
  printf '%s' "$v"
}

# --- Network ------------------------------------------------------------------
# service_bind: the address services listen on.
#   127.0.0.1 with userspace tailscaled (proot mode): tailnet connections are
#     handed to localhost, so services are reachable over Tailscale but not
#     from the Wi-Fi LAN.
#   0.0.0.0 otherwise (Tailscale app: traffic arrives on the VPN interface).
# Override with net.bind in the config.
service_bind() {
  local b
  b=$(cfg_get net.bind auto)
  if [[ "$b" == auto ]]; then
    if [[ "$(cfg_get tailscale.mode "")" == proot ]]; then b=127.0.0.1; else b=0.0.0.0; fi
  fi
  printf '%s' "$b"
}

# device_host: how other devices reach this one (for URLs shown to the user).
device_host() {
  local h
  h=$(cfg_get tailscale.dnsname "")
  [[ -n "$h" ]] && { printf '%s' "$h"; return; }
  h=$(ip -4 -o addr show 2>/dev/null | awk '$2 != "lo" { sub(/\/.*/, "", $4); print $4; exit }')
  printf '%s' "${h:-<device-address>}"
}
