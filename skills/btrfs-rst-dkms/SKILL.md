---
name: btrfs-rst-dkms
description: Deploy the RST-enabled btrfs DKMS module to a Linux host.
version: 1.0.0
author: z5n0w, Hermes Agent
license: GPL-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [btrfs, dkms, zoned, smr, zns, raid-stripe-tree, kernel-module]
    related_skills: []
---

# btrfs-rst-dkms Skill

Installs an out-of-tree **btrfs** kernel module built with
`CONFIG_BTRFS_EXPERIMENTAL` so the **raid-stripe-tree (RST)** feature is
available. RST is what allows btrfs **RAID1 / RAID10 / RAID0 on zoned block
devices** (host-managed SMR HDDs, ZNS SSDs).

Scope: this skill deploys **only the kernel module**. Creating/formatting an
RST filesystem is separate and additionally needs a `btrfs-progs` built with
`--enable-experimental` (`mkfs.btrfs -O rst`).

## When to Use

- A host must mount or use a btrfs filesystem that has the `raid-stripe-tree`
  feature, and mounting currently fails with:
  `BTRFS error (device sdX): cannot mount because of unknown incompat features (0x4000)`
- The user wants btrfs RAID1/RAID10 on zoned (SMR/ZNS) disks.
- Don't use for: creating/formatting filesystems, or ordinary non-zoned btrfs
  problems.

## Prerequisites

- Target host: Linux, with root/sudo. (Debian/Ubuntu assumed for apt fallbacks.)
- `dkms`, `build-essential`, and kernel headers for the running kernel:
  `linux-headers-$(uname -r)`.
- The **kernel source** for the running kernel's `MAJOR.MINOR` series
  (`linux-source-<maj.min>`). `scripts/prepare.sh` installs it automatically on
  Debian when missing; offline hosts must supply it via `KSRC=`.
- The repository: `https://github.com/z5n0w/btrfs-rst-dkms`

Two facts to keep in mind throughout:

- `CONFIG_BTRFS_EXPERIMENTAL` is a **compile-time** gate. There is no runtime
  switch — the module must be rebuilt. The only change to upstream btrfs is one
  line added to `fs/btrfs/Makefile` by
  `patches/0001-enable-config-btrfs-experimental.patch`.
- DKMS `EXTRA_CFLAGS` **cannot** enable it (it never reaches Kbuild and yields a
  module that still lacks RST). The flag must come from the Makefile.

## How to Run

All commands run through the `terminal` tool. For a remote host, prefix with
`ssh <user>@<host>` (e.g. `terminal(command="ssh user@host 'uname -r'")`).

## Procedure

1. **Recon the host** — know what you are working with before changing anything.

   ```sh
   uname -r
   test -d /lib/modules/$(uname -r)/build && echo headers-ok || echo headers-MISSING
   command -v dkms || echo dkms-MISSING
   lsmod | grep '^btrfs ' ; cat /sys/module/btrfs/refcnt 2>/dev/null
   findmnt -t btrfs -o TARGET,SOURCE
   ```

   Completion: you know the kernel release, that headers exist, whether `dkms`
   is installed, and whether btrfs is currently loaded/in use.

2. **Install prerequisites** if the recon showed gaps.

   ```sh
   sudo apt-get install -y dkms build-essential linux-headers-$(uname -r)
   ```

   Completion: `dkms` and `/lib/modules/$(uname -r)/build` both exist.

3. **Get the repo onto the host.**

   ```sh
   git clone https://github.com/z5n0w/btrfs-rst-dkms
   cd btrfs-rst-dkms
   ```

   Completion: `scripts/install.sh` exists in the working directory.

4. **Install the module.**

   ```sh
   sudo ./scripts/install.sh
   ```

   This stages `/usr/src/btrfs-rst-1.0` from kernel source, applies the patch,
   runs `dkms add/build/install`, and then attempts to load the new module.
   Re-runnable: it replaces a previously registered `btrfs-rst` package.

   Completion: the script ends with
   `==> OK: btrfs loaded with experimental=on` **or**, if btrfs was in use,
   `[!] btrfs is in use (refcnt != 0) ... reboot to activate`.

5. **Activate the new module** if step 4 reported btrfs in use. Unmount every
   btrfs filesystem (or reboot), then reload.

   ```sh
   sudo rmmod btrfs && sudo modprobe btrfs     # only when nothing uses btrfs
   ```

   Completion: `lsmod` shows `btrfs`, and `dmesg` shows the newest
   `Btrfs loaded, ...` line containing `experimental=on`.

6. **Verify.**

   ```sh
   sudo ./scripts/verify.sh; echo "rc=$?"
   ```

   Completion: exit code 0 and `PASS: experimental=on -> raid-stripe-tree is
   available`.

## Verification

The deployment is good when all three hold:

- `dkms status` lists `btrfs-rst/1.0, <kernel>: installed`.
- `dmesg | grep 'Btrfs loaded'` newest line contains `experimental=on`.
- `sudo ./scripts/verify.sh` exits 0.

Only then will an RST filesystem mount instead of failing with `0x4000`.

## Pitfalls

- **`0x4000` mount failure after "successful" install** — the module was built
  without `CONFIG_BTRFS_EXPERIMENTAL`. Confirm `dmesg` says `experimental=on`;
  if not, the Makefile patch did not apply — re-run `scripts/install.sh` and
  check that `grep subdir-ccflags-y /usr/src/btrfs-rst-1.0/Makefile` matches.
- **Module will not swap while btrfs is mounted.** `refcnt != 0` blocks
  `rmmod`; the fix is unmount or reboot, never force.
- **Unsigned-module taint** — `module verification failed: signature ...` is
  harmless unless Secure Boot is enforced; then
  `mokutil --import /var/lib/dkms/mok.pub` and reboot.
- **Kernel series mismatch** — source must match the running kernel's
  `MAJOR.MINOR`. A wrong series compiles-then-fails-to-load; re-run with
  `KSRC=/path/to/correct/linux-source-<maj.min>.tar.xz`.
- **Offline hosts** — `prepare.sh` needs a kernel source; preinstall
  `linux-source-<maj.min>` or pass `KSRC=<dir|tarball>`.
- **Experimental feature** — RST is gated behind `CONFIG_BTRFS_EXPERIMENTAL`
  and `mkfs.btrfs` warns it is not for production. Say so to the user; do not
  present it as production-ready.

## Troubleshooting

| Symptom | Action |
|---|---|
| `cannot mount ... unknown incompat features (0x4000)` | Module lacks EXPERIMENTAL. Re-run `scripts/install.sh`; then check `dmesg` for `experimental=on`. |
| `could not find kernel source for the '<x.y>' series` | `apt-get install linux-source-<x.y>` or pass `KSRC=…` to `install.sh`. |
| `ERROR: Kernel configuration is invalid` | Install `linux-headers-$(uname -r)`. |
| `dkms add` complains the package exists | Already handled by `install.sh`; if run manually, `dkms remove btrfs-rst/1.0 --all` first. |
| Signed-module / MOK errors | Enroll `/var/lib/dkms/mok.pub` with `mokutil`, or disable Secure Boot. |
