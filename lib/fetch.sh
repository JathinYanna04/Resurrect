# shellcheck shell=bash
# Downloads with mandatory checksum verification.

[[ -n "${_REZ_FETCH_LOADED:-}" ]] && return 0
_REZ_FETCH_LOADED=1

# shellcheck source=lib/versions.sh
source "$REZ_ROOT/lib/versions.sh"

: "${REZ_CACHE_DIR:=$REZ_DATA_DIR/cache}"

# go_arch [UNAME_M]: map the kernel's machine name to Go/release naming.
go_arch() {
  case "${1:-$(uname -m)}" in
    aarch64 | arm64) echo arm64 ;;
    armv7* | armv8l | arm) echo armv7 ;;
    x86_64 | amd64) echo amd64 ;;
    i686 | i386 | x86) echo 386 ;;
    *) echo unknown ;;
  esac
}

sha256_of() {
  if have sha256sum; then sha256sum "$1" | awk '{ print $1 }'
  else openssl dgst -sha256 -r "$1" | awk '{ print $1 }'
  fi
}

# fetch_verified URL SHA256 DEST: download to DEST unless a cached copy with
# the right checksum exists. Refuses an empty checksum.
fetch_verified() {
  local url=$1 want=$2 dest=$3 got
  [[ -n "$want" ]] || die "no pinned checksum for $url (refusing an unverified download)"
  if [[ -f "$dest" ]] && [[ "$(sha256_of "$dest")" == "$want" ]]; then
    debug "cached: $dest"
    return 0
  fi
  [[ "$REZ_DRY_RUN" == 1 ]] && { run_cmd curl -fL "$url" -o "$dest"; return 0; }
  mkdir -p "$(dirname "$dest")"
  info "downloading $url"
  curl -fL --retry 3 --connect-timeout 20 -o "$dest.part" "$url" || die "download failed: $url"
  got=$(sha256_of "$dest.part")
  if [[ "$got" != "$want" ]]; then
    rm -f "$dest.part"
    die "checksum mismatch for $url
  expected $want
  got      $got"
  fi
  mv -f "$dest.part" "$dest"
  ok "verified $(basename "$dest")"
}

# fetch_pinned TOOL: download the pinned release of TOOL for this device's
# architecture into the cache and print the local path.
fetch_pinned() {
  local tool=${1^^} arch version url_tpl url sha dest asset_arch version_var url_var
  arch=$(go_arch)
  local -n _shas="PIN_${tool}_SHA256"
  version_var="PIN_${tool}_VERSION"; version=${!version_var}
  url_var="PIN_${tool}_URL"; url_tpl=${!url_var}
  sha=${_shas[$arch]:-}
  [[ -n "$sha" ]] || die "${1} is not available for $(uname -m)"
  asset_arch=$arch
  [[ "$tool" == TAILSCALE && "$arch" == armv7 ]] && asset_arch=arm
  url=${url_tpl//\$\{version\}/$version}
  url=${url//\$\{arch\}/$asset_arch}
  dest="$REZ_CACHE_DIR/$(basename "$url")"
  fetch_verified "$url" "$sha" "$dest" >&2
  echo "$dest"
}

# --- Container images ----------------------------------------------------
# fetch_image_files IMAGE MANIFEST_DIGEST DEST PATH...
# Download the layers of one image manifest (pinned by digest) and extract
# PATHs into DEST. Works without docker: plain registry API over HTTPS.
fetch_image_files() {
  local image=$1 digest=$2 dest=$3; shift 3
  local reg=https://registry-1.docker.io token work manifest layer
  require_cmd curl jq tar
  work=$(mktemp -d "${TMPDIR:-/tmp}/rez-img.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" RETURN
  token=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$image:pull" | jq -r .token) \
    || die "registry auth failed for $image"
  curl -fsSL -H "Authorization: Bearer $token" \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
    -o "$work/manifest.json" "$reg/v2/$image/manifests/sha256:$digest" || die "manifest download failed"
  [[ "$(sha256_of "$work/manifest.json")" == "$digest" ]] || die "image manifest digest mismatch for $image"
  mkdir -p "$dest"
  for layer in $(jq -r '.layers[].digest' "$work/manifest.json"); do
    info "fetching layer ${layer:7:12}"
    curl -fsSL -H "Authorization: Bearer $token" -o "$work/layer" "$reg/v2/$image/blobs/$layer" \
      || die "layer download failed"
    [[ "sha256:$(sha256_of "$work/layer")" == "$layer" ]] || die "layer digest mismatch ($layer)"
    # Extract only what was asked for; missing paths in a layer are normal.
    tar -xzf "$work/layer" -C "$dest" "$@" 2>/dev/null || true
  done
  local p
  for p in "$@"; do
    [[ -e "$dest/$p" ]] || die "$p not found in $image"
  done
}
