# shellcheck shell=bash
# alerts: "smart alerts". You describe what you care about in plain words;
# an LLM (your key, any OpenAI-compatible endpoint) filters new items from
# feeds, APIs and web pages, and the hits arrive through ntfy.
# Jobs live in ~/.config/resurrect/alerts/*.toml (examples in alerts/examples/).

MOD_NAME=alerts
MOD_DESC="Smart alerts: LLM-filtered feeds/sites/APIs to ntfy (your API key)"
MOD_DEPENDS="base"
MOD_SERVICE=0
MOD_RAM_EST_MB=0
MOD_DISK_EST_MB=5
MOD_TESTED="Linux + termux-docker: parsing, dedupe, scoring (mock LLM), ntfy, cron lines. Live LLM: user's endpoint"

AL_JOBS=$REZ_CONFIG_DIR/alerts
_py() { python3 "$REZ_ROOT/alerts/smart_alerts.py" "$@"; }

mod_configure() {
  secret_get alerts_api_key >/dev/null && return 0
  local f k=''
  f=$(cfg_get alerts.api_key_file "")
  if [[ -n "$f" ]]; then k=$(head -n1 "${f/#\~/$HOME}"); cfg_unset alerts.api_key_file
  elif [[ $(ui_mode) != none ]]; then
    k=$(ui_password "Smart alerts" "API key for your OpenAI-compatible LLM endpoint (empty = add later with: rez alerts set-key)")
  fi
  [[ -n "$k" ]] && secret_set alerts_api_key "$k"
  return 0
}

mod_install() {
  python3 -c 'import tomllib' 2>/dev/null || die "smart alerts need Python 3.11+ (pkg install python)"
  ensure_dir 700 "$AL_JOBS"
  local f
  for f in "$REZ_ROOT"/alerts/examples/*.toml; do
    [[ -e "$AL_JOBS/${f##*/}" ]] || run_cmd install -m 600 "$f" "$AL_JOBS/${f##*/}"
  done
  ok "example jobs copied to $AL_JOBS (all disabled; edit, set enabled = true, then rez alerts sync)"
}

mod_cron() {
  [[ -d "$AL_JOBS" ]] || return 0
  _py cron-lines "$AL_JOBS" "$(rez_cmd)" "$REZ_LOG_DIR" 2>/dev/null
}

mod_status() {
  local on
  on=$(_py list "$AL_JOBS" 2>/dev/null | awk '$2 == "on"' | wc -l)
  printf '%-14s %s job(s) enabled in %s\n' alerts "$on" "$AL_JOBS"
}

mod_health() {
  # A job that failed 3+ times in a row is unhealthy.
  local db="$REZ_STATE_DIR/alerts.db" bad
  [[ -f "$db" ]] || return 0
  bad=$(sqlite3 "$db" "SELECT group_concat(job, ' ') FROM kv WHERE k='failures' AND CAST(v AS INTEGER) >= 3;" 2>/dev/null)
  [[ -z "$bad" ]] || { echo "failing jobs: $bad"; return 1; }
}

mod_backup() {
  mkdir -p "$1"
  cp -a "$AL_JOBS" "$1/jobs" 2>/dev/null || true
  [[ -f "$REZ_STATE_DIR/alerts.db" ]] && sqlite3 "$REZ_STATE_DIR/alerts.db" ".backup '$1/alerts.db'"
  return 0
}

mod_uninstall() {
  [[ "${REZ_PURGE:-0}" == 1 ]] && run_cmd rm -rf "$AL_JOBS" "$REZ_STATE_DIR/alerts.db"
  return 0
}

mod_info() { printf 'Alerts:     jobs in %s (rez alerts list)\n' "$AL_JOBS"; }

_job() {
  local j=${1:?job name}
  [[ -f "$AL_JOBS/$j.toml" ]] && { echo "$AL_JOBS/$j.toml"; return; }
  [[ -f "$j" ]] && { echo "$j"; return; }
  die "no job $j in $AL_JOBS"
}

mod_cli() {
  local cmd=${1:-}; (($#)) && shift
  case "$cmd" in
    list) _py list "$AL_JOBS" ;;
    run)
      local j; j=$(_job "${1:-}"); shift
      # bin/rez consumes --dry-run as a global option; hand it back to the job.
      [[ "$REZ_DRY_RUN" == 1 ]] && set -- "$@" --dry-run
      _py run "$j" "$@" ;;
    test) _py test "$(_job "${1:-}")" ;;
    sync) base_sync_boot_and_cron; ok "cron updated from enabled jobs" ;;
    set-key) secret_set alerts_api_key "$(ui_password "Smart alerts" "API key")"; ok "key saved" ;;
    *) die "usage: rez alerts list|run JOB [--dry-run] [--no-llm]|test JOB|sync|set-key" ;;
  esac
}
