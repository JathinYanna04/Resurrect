# shellcheck shell=bash
# Debian userland via proot-distro. Used for programs that expect a normal
# Linux filesystem (/etc/resolv.conf, /etc/ssl, /var/lib): tailscaled, ntfy,
# Jellyfin. No root needed; proot fakes it with ptrace.

[[ -n "${_REZ_PROOT_LOADED:-}" ]] && return 0
_REZ_PROOT_LOADED=1

: "${REZ_PROOT_DISTRO:=debian}"
# For svc_start, which needs a real command rather than a shell function.
PROOT_CMD=(proot-distro login "$REZ_PROOT_DISTRO" --)

# proot_rootfs: path of the Debian rootfs as seen from Termux.
# proot-distro moved it between versions, so try both layouts.
proot_rootfs() {
  local base="$PREFIX/var/lib/proot-distro" d
  for d in "$base/containers/$REZ_PROOT_DISTRO/rootfs" "$base/installed-rootfs/$REZ_PROOT_DISTRO"; do
    [[ -d "$d/etc" ]] && { echo "$d"; return 0; }
  done
  return 1
}

proot_installed() { proot_rootfs >/dev/null; }

proot_install() {
  if proot_installed; then
    ok "proot Debian already installed"
    return 0
  fi
  run pkg install -y proot-distro
  info "installing Debian with proot-distro (~150 MB download)"
  run proot-distro install "$REZ_PROOT_DISTRO"
  run proot_exec sh -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl'
}

# proot_exec CMD...: run CMD inside Debian. The process tree is
# proot -> CMD, so CMD's /proc cmdline is its own argv (proc_matches works).
proot_exec() {
  proot-distro login "$REZ_PROOT_DISTRO" -- "$@"
}

# proot_apt PKG...: install Debian packages inside the rootfs.
proot_apt() {
  run proot_exec env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

# proot_put SRC DEST_IN_ROOTFS [MODE]: copy a file into the rootfs.
proot_put() {
  local src=$1 dest=$2 mode=${3:-644} root
  root=$(proot_rootfs) || die "proot Debian is not installed"
  run install -D -m "$mode" "$src" "$root$dest"
}
