#!/usr/bin/env bash
#
# Remove the DKMS btrfs-rst module and restore the distribution's btrfs.ko.
# Must be run as root.
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KVER="$(uname -r)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "run as root: sudo $0"

PKG="$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p'  "$SRC_DIR/dkms.conf")"
VER="$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$SRC_DIR/dkms.conf")"
REF="$PKG/$VER"

log "removing $REF (all kernels); the original module is restored automatically"
dkms remove "$REF" --all || warn "dkms remove reported an error (already removed?)"

depmod -a

# Reload the distro module if it is safe to do so.
if lsmod | grep '^btrfs ' >/dev/null; then
  if [[ "$(cat /sys/module/btrfs/refcnt 2>/dev/null || echo 1)" == "0" ]]; then
    rmmod btrfs && modprobe btrfs || warn "reload failed; reboot to restore the distro module"
  else
    warn "btrfs is in use; reboot to restore the distribution module"
  fi
fi

# remove the staged build tree (if present)
rm -rf "/usr/src/${PKG}-${VER}" 2>/dev/null || true

log "done. dmesg should now show 'Btrfs loaded, zoned=yes, fsverity=yes' (no experimental=on)."
