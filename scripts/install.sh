#!/usr/bin/env bash
#
# Build and install the out-of-tree btrfs module with raid-stripe-tree (RST)
# support for the running kernel. Must be run as root. See ../README.md.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KVER="$(uname -r)"

PKG="$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p'  "$REPO/dkms.conf")"
VER="$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$REPO/dkms.conf")"
[[ -n "$PKG" && -n "$VER" ]] || { echo "cannot parse dkms.conf" >&2; exit 1; }
REF="$PKG/$VER"
: "${BUILD_DIR:=/usr/src/${PKG}-${VER}}"
export BUILD_DIR

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "run as root: sudo $0"

# --- prerequisites ---------------------------------------------------------
command -v dkms >/dev/null 2>&1 || die "dkms not installed (apt-get install dkms)"
[[ -d "/lib/modules/${KVER}/build" ]] \
  || die "kernel headers for ${KVER} missing; install linux-headers-${KVER}"
command -v make >/dev/null 2>&1 || die "make not found (apt-get install build-essential)"
command -v gcc  >/dev/null 2>&1 || die "gcc not found (apt-get install build-essential)"

# --- stage the build tree from kernel source -------------------------------
log "preparing build tree ($BUILD_DIR)"
"$REPO/scripts/prepare.sh"

# --- build & install -------------------------------------------------------
# Make install.sh re-runnable: drop any previously registered package first.
if [[ -n "$(dkms status "$REF" 2>/dev/null)" ]]; then
  log "replacing existing DKMS package $REF"
  dkms remove "$REF" --all || true
fi

log "dkms add"
dkms add "$BUILD_DIR"

log "dkms build"
dkms build "$REF" -k "$KVER"

log "dkms install"
dkms install "$REF" -k "$KVER"

log "installed:"
dkms status "$REF" -k "$KVER" || true

# --- activate the new module if possible -----------------------------------
if lsmod | grep '^btrfs ' >/dev/null; then
  if [[ "$(cat /sys/module/btrfs/refcnt 2>/dev/null || echo 1)" == "0" ]]; then
    log "unloading running btrfs module"
    rmmod btrfs || warn "rmmod failed; reboot to activate the new module"
  else
    warn "btrfs is in use (refcnt != 0); unmount btrfs filesystems or reboot to activate"
  fi
fi
modprobe btrfs 2>/dev/null || true

# --- verify ----------------------------------------------------------------
# NOTE: use 'grep ... >/dev/null' (not 'grep -q') — under 'set -o pipefail' a
# 'grep -q' that exits early SIGPIPEs the producer and the pipeline "fails".
if dmesg 2>/dev/null | grep 'Btrfs loaded, experimental=on' >/dev/null; then
  log "OK: btrfs loaded with experimental=on (raid-stripe-tree available)"
else
  warn "could not confirm 'experimental=on' yet; run scripts/verify.sh or reboot, then re-check"
fi
