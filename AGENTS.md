# AGENTS.md

Guidance for AI coding agents working **on this repository**.

> Deploying the module to a host is a different job — use
> [`skills/btrfs-rst-dkms/SKILL.md`](skills/btrfs-rst-dkms/SKILL.md) for that.

## What this repo is

A DKMS package that builds the Linux **btrfs** kernel module **out-of-tree**
with `CONFIG_BTRFS_EXPERIMENTAL` enabled, which unlocks the
**raid-stripe-tree (RST)** incompat feature. RST is what makes btrfs
RAID1/RAID10/RAID0 usable on zoned block devices (host-managed SMR HDDs, ZNS
SSDs). Most distro kernels ship `# CONFIG_BTRFS_EXPERIMENTAL is not set`, so
they cannot mount an RST filesystem — this package supplies a module that can.

## Layout

```
dkms.conf                                   # package btrfs-rst/1.0
patches/0001-enable-config-btrfs-experimental.patch   # the only source change
scripts/prepare.sh        # fetch fs/btrfs from kernel source, stage /usr/src/btrfs-rst-1.0
scripts/install.sh        # prepare + dkms add/build/install + activate + verify
scripts/uninstall.sh      # dkms remove + restore distro module + clean up
scripts/verify.sh         # assert the loaded module is experimental=on
skills/btrfs-rst-dkms/SKILL.md   # deployment skill for an operator agent
```

## Invariants — do not break these

1. **Do not vendor `fs/btrfs`.** The repo intentionally carries no btrfs
   sources; `prepare.sh` obtains them from the kernel source tree at build
   time. Adding a vendored copy bloats the repo and re-distributes GPL kernel
   code needlessly.
2. **The only change to upstream btrfs is the one-line patch.** It adds
   `subdir-ccflags-y += -DCONFIG_BTRFS_EXPERIMENTAL` to `fs/btrfs/Makefile`.
   Never add further source edits here — if upstream needs a fix, it belongs
   upstream.
3. **Never enable EXPERIMENTAL via DKMS `EXTRA_CFLAGS`.** It does not reach the
   Kbuild compile stage: the module builds and loads fine but lacks the RST
   feature, so every RST mount fails with
   `cannot mount because of unknown incompat features (0x4000)`. The flag must
   live in the Makefile (the patch).
4. **Scripts use `set -euo pipefail`. Do not use `grep -q` in a pipeline.**
   `grep -q` exits at the first match and SIGPIPEs the producer, which
   `pipefail` then reports as a failed pipeline. Use `grep … >/dev/null`.
5. **Trap/cleanup functions must return 0.** A helper ending in
   `[[ -n "$x" ]] && rm -rf "$x"` returns 1 when `$x` is empty, and as an
   `EXIT` trap that rewrites the script's exit status (breaks callers under
   `set -e`). Use `if [[ -n "$x" ]]; then rm -rf "$x"; fi`.
6. **`install.sh` must stay re-runnable.** It removes a previously registered
   `btrfs-rst` package before `dkms add`.
7. **Keep it module-scoped.** Filesystem creation (`mkfs.btrfs -O rst`) needs a
   separate experimental `btrfs-progs` and is out of scope for this repo.

## Commands

| Task | Command |
|---|---|
| Syntax-check the scripts | `for f in scripts/*.sh; do bash -n "$f"; done` |
| Apply the patch by hand | `patch -p1 -d <fs/btrfs-dir> < patches/0001-enable-config-btrfs-experimental.patch` |
| Deploy (root, on the target) | `sudo ./scripts/install.sh` |
| Verify | `sudo ./scripts/verify.sh; echo rc=$?` |
| Uninstall | `sudo ./scripts/uninstall.sh` |

## Validating changes

There is no CI and no test suite. Before committing:

1. `bash -n` every script you touched.
2. If you touched the patch, dry-run it against a real tree:
   `patch --dry-run -p1 -d /usr/src/linux-source-<ver>/fs/btrfs < patches/0001-…patch`
   (must report "checking file Makefile" with no rejects).
3. If you touched `prepare.sh`/`install.sh`, exercise the real path on a host
   that has the matching kernel headers + `linux-source-<maj.min>`, and confirm
   `install.sh` ends with `==> OK: btrfs loaded with experimental=on` and that
   `prepare.sh` exits 0 (it is called under `set -e`).
4. Confirm the repo stays lean: `git ls-files | wc -l` should stay in the low
   tens (no `*.c`/`*.h`).

## Conventions

- Shell: POSIX-ish bash, `set -euo pipefail`, `log/warn/die` helpers, no
  machine-local paths.
- Docs are English. Keep README (users) / AGENTS.md (contributors) /
  SKILL.md (operator agents) non-overlapping.
- Commits: imperative subject, explain *why* in the body. Do not commit build
  artifacts (`.gitignore` covers them).

## License

GPL-2.0 (the patch targets Linux kernel code).
