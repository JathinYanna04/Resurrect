# shellcheck shell=bash
# ntfy client used by every alerting path (supervisor, monitor, backups, smart alerts).

[[ -n "${_REZ_NOTIFY_LOADED:-}" ]] && return 0
_REZ_NOTIFY_LOADED=1

# shellcheck source=lib/config.sh
source "$REZ_ROOT/lib/config.sh"

# notify_send TITLE MESSAGE [PRIORITY 1-5] [TAGS]
# Never fails the caller: alerts are best effort and logged when undeliverable.
notify_send() {
  local title=$1 msg=$2 prio=${3:-3} tags=${4:-} url topic token
  url=$(cfg_get ntfy.url "")
  topic=$(cfg_get ntfy.topic "")
  if [[ -z "$url" || -z "$topic" ]]; then
    _log_file "NOTIFY (ntfy not configured) $title: $msg"
    return 0
  fi
  token=$(secret_get ntfy_publish_token 2>/dev/null || true)
  local -a hdr=(-H "Title: $title" -H "Priority: $prio")
  [[ -n "$token" ]] && hdr+=(-H "Authorization: Bearer $token")
  [[ -n "$tags" ]] && hdr+=(-H "Tags: $tags")
  curl -fsS -m 15 --retry 2 "${hdr[@]}" \
    -d "$msg" "$url/$topic" >/dev/null 2>&1 \
    || _log_file "NOTIFY FAILED $title: $msg"
  return 0
}
