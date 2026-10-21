#!/usr/bin/env bash
# Run the test suite inside the official Termux Docker image: the real
# Termux userland ($PREFIX, pkg, Termux's bash/coreutils/python) but no
# Android underneath (no getprop, Termux:Boot, root or proot ptrace).
#
#   tests/termux-docker/run.sh            unit tests (bats + python)
#   tests/termux-docker/run.sh --install  also a real install (integration.sh)
#   tests/termux-docker/run.sh --integration  only the real install
#
# The test image (Termux + test dependencies) is built once from the
# Dockerfile next to this script.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
image=${REZ_TEST_IMAGE:-resurrect-test}
mode=${1:-unit}

if ! docker image inspect "$image" >/dev/null 2>&1; then
  echo "==> building $image (one time, downloads Termux packages)"
  docker build -t "$image" "$here"
fi

# The checkout is mounted read-only and copied, so tests can never modify it.
# Every stage runs even if an earlier one fails; the summary lists them all.
docker run --rm -i -v "$repo:/repo:ro" -e MODE="$mode" "$image" bash -s <<'INNER'
set -uo pipefail
cp -a /repo "$HOME/resurrect"
cd "$HOME/resurrect" || exit 1
echo "==> $(bats --version), $(python --version), $(bash --version | head -1)"
results=()
if [ "$MODE" != --integration ]; then
  BATS_TEST_TIMEOUT=90 bats tests/bats && results+=("bats: ok") || results+=("bats: FAILED")
  python -m unittest discover -s tests/python 2>&1 | tail -n 3
  [ "${PIPESTATUS[0]}" -eq 0 ] && results+=("python: ok") || results+=("python: FAILED")
fi
if [ "$MODE" = --install ] || [ "$MODE" = --integration ]; then
  bash tests/termux-docker/integration.sh && results+=("integration: ok") || results+=("integration: FAILED")
fi
echo "==> summary"
printf '  %s\n' "${results[@]}"
[[ " ${results[*]} " != *FAILED* ]]
INNER
