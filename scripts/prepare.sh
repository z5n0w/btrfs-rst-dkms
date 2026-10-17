#!/usr/bin/env bash
#
# Stage the DKMS build tree for the running kernel:
#   * take fs/btrfs from a matching kernel source tree (or tarball),
#   * apply the one-line CONFIG_BTRFS_EXPERIMENTAL patch,
#   * drop in dkms.conf,
#   * write the result to /usr/src/<pkg>-<ver>  (DKMS's expected location).
#
# No btrfs source is stored in this repo; it is obtained at build time.
# Must be run as root.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KVER="$(uname -r)"
SERIES="$(printf '%s' "$KVER" | grep -oE '^[0-9]+\.[0-9]+' || true)"

PKG="$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p'  "$REPO/dkms.conf")"
VER="$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$REPO/dkms.conf")"
[[ -n "$PKG" && -n "$VER" ]] || { echo "cannot parse dkms.conf" >&2; exit 1; }

BUILD_DIR="${BUILD_DIR:-/usr/src/${PKG}-${VER}}"
PATCH="$REPO/patches/0001-enable-config-btrfs-experimental.patch"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "run as root: sudo $0"

tmp=""
cleanup() { if [[ -n "$tmp" ]]; then rm -rf "$tmp"; fi; }   # must return 0 (EXIT trap)
trap cleanup EXIT

# Return the fs/btrfs dir for a directory that is either a kernel source root
# or already the fs/btrfs dir itself.
btrfs_in_dir() {
  if   [[ -d "$1/fs/btrfs" ]]; then printf '%s/fs/btrfs\n' "$1"
  elif [[ -d "$1" && -f "$1/Makefile" && -f "$1/fs.h" ]]; then printf '%s\n' "$1"
  fi
}

btrfs_src=""

# 1) explicit override: KSRC=<kernel-source-dir | fs/btrfs-dir | tarball>
if [[ -n "${KSRC:-}" ]]; then
  if [[ -f "$KSRC" ]]; then
    tmp="$(mktemp -d)"; log "extracting KSRC=$KSRC"
    tar xf "$KSRC" -C "$tmp"
    btrfs_src="$(find "$tmp" -type d -path '*/fs/btrfs' | head -1)"
  else
    btrfs_src="$(btrfs_in_dir "$KSRC")"
  fi
  [[ -n "$btrfs_src" ]] || die "KSRC=$KSRC does not contain fs/btrfs"
fi

# 2) Debian kernel source already extracted under /usr/src
if [[ -z "$btrfs_src" && -n "$SERIES" && -d "/usr/src/linux-source-${SERIES}/fs/btrfs" ]]; then
  btrfs_src="/usr/src/linux-source-${SERIES}/fs/btrfs"
fi

# 3) kernel source tarball in /usr/src
if [[ -z "$btrfs_src" && -n "$SERIES" && -f "/usr/src/linux-source-${SERIES}.tar.xz" ]]; then
  tmp="$(mktemp -d)"; log "extracting /usr/src/linux-source-${SERIES}.tar.xz"
  tar xf "/usr/src/linux-source-${SERIES}.tar.xz" -C "$tmp"
  btrfs_src="$(find "$tmp" -type d -path '*/fs/btrfs' | head -1)"
fi

# 4) install the matching kernel source package
if [[ -z "$btrfs_src" && -n "$SERIES" ]] && command -v apt-get >/dev/null 2>&1; then
  log "installing linux-source-${SERIES} ..."
  apt-get update -qq || true
  if apt-get install -y "linux-source-${SERIES}"; then
    if   [[ -d "/usr/src/linux-source-${SERIES}/fs/btrfs" ]]; then
      btrfs_src="/usr/src/linux-source-${SERIES}/fs/btrfs"
    elif [[ -f "/usr/src/linux-source-${SERIES}.tar.xz" ]]; then
      tmp="$(mktemp -d)"; tar xf "/usr/src/linux-source-${SERIES}.tar.xz" -C "$tmp"
      btrfs_src="$(find "$tmp" -type d -path '*/fs/btrfs' | head -1)"
    fi
  fi
fi

[[ -n "$btrfs_src" && -d "$btrfs_src" ]] || die "could not find kernel source for the '${SERIES}' series.
  Install it, e.g.:
      apt-get install linux-source-${SERIES}
  or point at a tree/tarball:
      sudo KSRC=/path/to/linux-source-${SERIES}.tar.xz $0"

log "kernel    : $KVER (series ${SERIES:-?})"
log "btrfs src : $btrfs_src"
log "build dir : $BUILD_DIR"

# --- stage -----------------------------------------------------------------
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cp -a "$btrfs_src"/. "$BUILD_DIR"/
cp -a "$REPO/dkms.conf" "$BUILD_DIR/dkms.conf"

# --- apply the EXPERIMENTAL patch ------------------------------------------
if grep -q 'subdir-ccflags-y += -DCONFIG_BTRFS_EXPERIMENTAL' "$BUILD_DIR/Makefile"; then
  log "patch already present"
elif command -v patch >/dev/null 2>&1 \
     && patch -d "$BUILD_DIR" -p1 --forward --silent < "$PATCH"; then
  log "applied $(basename "$PATCH")"
else
  warn "patch(1) unavailable/failed; falling back to sed"
  sed -i '1a subdir-ccflags-y += -DCONFIG_BTRFS_EXPERIMENTAL' "$BUILD_DIR/Makefile"
  log "applied via sed"
fi

grep -q 'subdir-ccflags-y += -DCONFIG_BTRFS_EXPERIMENTAL' "$BUILD_DIR/Makefile" \
  || die "failed to enable CONFIG_BTRFS_EXPERIMENTAL in $BUILD_DIR/Makefile"

log "ready: $BUILD_DIR"
