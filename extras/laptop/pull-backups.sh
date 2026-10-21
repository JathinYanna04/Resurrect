#!/usr/bin/env bash
# shellcheck disable=SC2012  # ls on our own fixed names (resurrect-DATE.tar.gz)
# Copy resurrect's nightly backups from the phone to this computer.
#
#   pull-backups.sh PHONE [DEST]
#     PHONE  ssh destination: an ~/.ssh/config alias, or user@address
#            (Termux's sshd listens on port 8022; set it in ~/.ssh/config or
#            with REZ_SSH_PORT)
#     DEST   where to keep copies (default ~/resurrect-backups/PHONE)
#
# Environment: REZ_KEEP (default 14), REZ_SSH_PORT (default 8022),
#              REZ_REMOTE_DIR (default resurrect-backups, relative to the phone's home)
#
# Safety rules:
#   * Never --delete: a wiped or broken phone can never delete your copies.
#     Old copies are pruned here, by date, keeping the newest REZ_KEEP.
#   * Every archive is checked against the checksum the phone wrote.
#   * Phone unreachable (you are away, it is rebooting) = log and exit 0.
#   * After a good pull the phone is told (`rez backup mark-pulled`), so it
#     can alert you when no pull has happened for 3 days.
# Run it daily with systemd (systemd/), launchd or cron; see README.md.
set -euo pipefail

phone=${1:?usage: pull-backups.sh PHONE [DEST]}
dest=${2:-$HOME/resurrect-backups/$phone}
keep=${REZ_KEEP:-14}
remote=${REZ_REMOTE_DIR:-resurrect-backups}
ssh_bin=${REZ_SSH:-ssh}
ssh_cmd=("$ssh_bin" -o BatchMode=yes -o ConnectTimeout=15 -p "${REZ_SSH_PORT:-8022}")

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

mkdir -p "$dest"
chmod 700 "$dest"
if ! "${ssh_cmd[@]}" "$phone" true 2>/dev/null; then
  echo "$(date '+%F %T') $phone unreachable, skipping"
  exit 0
fi

rsync -a --partial --include='resurrect-*.tar.gz' --include='resurrect-*.tar.gz.sha256' --exclude='*' \
  -e "${ssh_cmd[*]}" "$phone:$remote/" "$dest/"
# rsync -a copies the source folder's mode onto $dest; backups hold secrets.
chmod 700 "$dest"

bad=0 n=0
for f in "$dest"/resurrect-*.tar.gz; do
  [[ -e "$f" ]] || continue
  if [[ -f "$f.sha256" ]]; then
    want=$(cut -d' ' -f1 <"$f.sha256")
    if [[ "$(sha256 "$f")" != "$want" ]]; then
      echo "checksum MISMATCH: ${f##*/}" >&2
      bad=1
    fi
  fi
  n=$((n + 1))
done
((bad == 0)) || exit 1
((n > 0)) || { echo "no backups on $phone yet"; exit 0; }

# Keep the newest $keep (names sort by date).
ls -1 "$dest"/resurrect-*.tar.gz | sort -r | tail -n +"$((keep + 1))" | while read -r old; do
  rm -f "$old" "$old.sha256"
done

"${ssh_cmd[@]}" "$phone" 'rez backup mark-pulled' || echo "warning: could not tell the phone about this pull" >&2
newest=$(ls -1 "$dest"/resurrect-*.tar.gz | sort | tail -n1)
echo "$(date '+%F %T') pulled from $phone: $(ls -1 "$dest"/resurrect-*.tar.gz | wc -l | tr -d ' ') kept, newest ${newest##*/}"
