#!/usr/bin/env bash
# resurrect bootstrap: raise your dead phone as a homelab.
#
#   curl -fsSL https://raw.githubusercontent.com/JathinYanna04/resurrect/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --profile lite --modules vaultwarden,ntfy --yes
#
# Or, if you would rather read it first (recommended):
#   pkg install -y git && git clone https://github.com/JathinYanna04/resurrect ~/.resurrect
#   less ~/.resurrect/install.sh && ~/.resurrect/install.sh
#
# What this script does, and nothing more:
#   1. checks it runs inside Termux
#   2. updates Termux packages and installs git, curl, jq, dialog, util-linux
#   3. clones resurrect into ~/.resurrect (or uses the checkout it runs from)
#   4. starts `rez setup`, which asks before installing anything else
# It never needs root, never flashes or reboots anything.

# Everything lives in main(), called on the last line, so a download cut off
# halfway through runs nothing.
main() {
  set -euo pipefail
  local repo=${REZ_REPO:-https://github.com/JathinYanna04/resurrect}
  local ref=${REZ_REF:-main}
  local dest=${REZ_HOME:-$HOME/.resurrect}
  local here=''

  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    [[ -x "$here/bin/rez" ]] || here=''
  fi

  if [[ "${PREFIX:-}" != */com.termux/* && "${REZ_ALLOW_NON_TERMUX:-0}" != 1 ]]; then
    echo "resurrect runs inside Termux on Android. Install Termux from F-Droid or GitHub (not Google Play)." >&2
    exit 1
  fi
  if [[ "${TERMUX_APK_RELEASE:-}" == GOOGLE_PLAY_STORE ]]; then
    echo "warning: this Termux comes from Google Play, which is outdated. Package installs may fail." >&2
    echo "         Install Termux from F-Droid or https://github.com/termux/termux-app/releases" >&2
  fi

  if [[ "${REZ_ALLOW_NON_TERMUX:-0}" != 1 ]]; then
    echo "==> updating Termux packages"
    pkg update -y
    pkg upgrade -y -o Dpkg::Options::=--force-confold
    pkg install -y git curl jq dialog util-linux
  fi

  if [[ -n "$here" ]]; then
    dest=$here
    echo "==> using this checkout: $dest"
  elif [[ -d "$dest/.git" ]]; then
    echo "==> updating $dest"
    git -C "$dest" pull --ff-only
  else
    echo "==> downloading resurrect into $dest"
    git clone --depth 1 --branch "$ref" "$repo" "$dest"
  fi

  echo "==> starting setup"
  exec bash "$dest/bin/rez" setup "$@"
}

main "$@"
