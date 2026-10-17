#!/usr/bin/env bash
#
# Verify that the running btrfs module is the RST-enabled one.
# Best run as root (needs dmesg).
#
set -uo pipefail

KVER="$(uname -r)"
rc=0

echo "kernel: $KVER"
echo

echo "--- loaded module ---"
if lsmod | grep '^btrfs ' >/dev/null; then
  lsmod | grep '^btrfs '
else
  echo "btrfs is NOT loaded"
fi
echo

echo "--- dkms status ---"
dkms status 2>/dev/null || echo "(dkms not available)"
echo

echo "--- module file used ---"
modinfo -F filename btrfs 2>/dev/null \
  || /sbin/modinfo -F filename btrfs 2>/dev/null \
  || echo "(modinfo unavailable)"
echo

echo "--- kernel load message ---"
msg="$(dmesg 2>/dev/null | grep 'Btrfs loaded' | tail -1 || true)"
if [[ -z "$msg" ]]; then
  msg="$(journalctl -k -b 2>/dev/null | grep 'Btrfs loaded' | tail -1 || true)"
fi
echo "${msg:-<none found>}"
echo

echo "--- RST feature check ---"
if grep -q 'experimental=on' <<<"$msg"; then
  echo "PASS: experimental=on -> raid-stripe-tree is available"
else
  echo "FAIL: module loaded WITHOUT experimental -> RST unavailable"
  echo "      rebuild with scripts/install.sh and make sure dmesg says 'experimental=on'"
  rc=1
fi

exit $rc
