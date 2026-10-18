# btrfs-rst-dkms

An out-of-tree build of the Linux **btrfs** kernel module with
`CONFIG_BTRFS_EXPERIMENTAL` enabled, so the **raid-stripe-tree (RST)** feature
is available on the running kernel.

RST is what makes **RAID1 / RAID10 (and RAID0) usable on zoned block devices**
(host-managed SMR HDDs, ZNS SSDs). Without it, stock distro kernels reject an
RST filesystem at mount time with:

```
BTRFS error (device sdX): cannot mount because of unknown incompat features (0x4000)
```

(`0x4000` is the `RAID_STRIPE_TREE` incompat bit.)

## Why a rebuild is required

`CONFIG_BTRFS_EXPERIMENTAL` is a **compile-time** Kconfig gate. The RST bit is
only added to `BTRFS_FEATURE_INCOMPAT_SUPP` inside an
`#ifdef CONFIG_BTRFS_EXPERIMENTAL` block (`fs/fs.h`), and most distro kernels
ship with `# CONFIG_BTRFS_EXPERIMENTAL is not set`. There is no runtime switch —
the module must be recompiled with that symbol defined.

## How this repo does it (no vendored source)

It does **not** carry a copy of the btrfs sources. The only change to upstream
btrfs is a **single line** in the `fs/btrfs/Makefile`:

```make
subdir-ccflags-y += -DCONFIG_BTRFS_EXPERIMENTAL
```

At install time, `scripts/prepare.sh`:

1. locates kernel source for the running kernel's series
   (`/usr/src/linux-source-<maj.min>/`, a `linux-source-<maj.min>.tar.xz`, or
   installs `linux-source-<maj.min>` via apt),
2. copies its `fs/btrfs` into `/usr/src/btrfs-rst-1.0`,
3. applies `patches/0001-enable-config-btrfs-experimental.patch`,
4. drops in `dkms.conf`.

`scripts/install.sh` then runs DKMS on that tree.

> **Note:** DKMS's own `EXTRA_CFLAGS` cannot be used for this — it does not
> reach the Kbuild compile stage and silently yields a module that still lacks
> the RST feature. The flag must live in the Makefile, which is what the patch
> does.

## Layout

```
.
├── dkms.conf                                  # DKMS package (btrfs-rst/1.0)
├── patches/
│   └── 0001-enable-config-btrfs-experimental.patch
├── scripts/
│   ├── prepare.sh        # stage /usr/src/btrfs-rst-1.0 from kernel source
│   ├── install.sh        # prepare + dkms add/build/install + swap + verify
│   ├── uninstall.sh      # dkms remove + restore distro module + clean up
│   └── verify.sh         # confirm the loaded module really has RST
├── AGENTS.md             # guidance for AI agents editing this repo
├── LICENSE               # GPL-2.0
├── README.md
└── skills/
    └── btrfs-rst-dkms/SKILL.md   # AI-assistant deployment skill
```

## AI assistant deployment

This repo ships an agent-readable skill at `skills/btrfs-rst-dkms/SKILL.md`.
Point an AI assistant (Hermes Agent, Claude Code, …) at that file or at the
repo, and it can recon a target host, install prerequisites, run
`scripts/install.sh`, activate and verify the module, and handle the common
failure modes. The skill covers only the kernel module; filesystem creation is
out of scope.

## Requirements

- `dkms`
- kernel headers for the running kernel (`linux-headers-$(uname -r)`)
- `build-essential` (gcc, make)
- the matching kernel **source** (the script can install it for you on Debian)

```sh
sudo apt-get install -y dkms build-essential linux-headers-$(uname -r)
```

## Install

```sh
git clone <this-repo> btrfs-rst-dkms
cd btrfs-rst-dkms
sudo ./scripts/install.sh
```

If `btrfs` is already in use the script cannot reload it and tells you to
reboot. The new module takes effect on the next load of `btrfs`
(`updates/dkms` has precedence over the in-kernel module).

Manual equivalent:

```sh
sudo ./scripts/prepare.sh
sudo dkms add     /usr/src/btrfs-rst-1.0
sudo dkms build   btrfs-rst/1.0 -k "$(uname -r)"
sudo dkms install btrfs-rst/1.0 -k "$(uname -r)"
sudo rmmod btrfs && sudo modprobe btrfs   # btrfs must not be in use
```

## Verify

```sh
sudo ./scripts/verify.sh
```

Expected kernel log line:

```
Btrfs loaded, experimental=on, zoned=yes, fsverity=yes
```

`experimental=on` means RST is registered and RST filesystems can be mounted.

## Uninstall

```sh
sudo ./scripts/uninstall.sh
```

Removes the DKMS module, restores the distribution's original `btrfs.ko`, and
deletes the staged build tree.

## Choosing the kernel source

`prepare.sh` auto-detects the source for the running kernel's `MAJOR.MINOR`
series. To use a specific tree or tarball instead:

```sh
sudo KSRC=/path/to/linux-source-7.1.tar.xz ./scripts/install.sh
# or
sudo KSRC=/usr/src/linux-7.1 ./scripts/install.sh
```

The source **must be the same series as the running kernel**: the module is
built against the running kernel's headers, and a mismatched source tree will
either fail to compile or refuse to load.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `cannot mount because of unknown incompat features (0x4000)` | Module built without `CONFIG_BTRFS_EXPERIMENTAL`. `dmesg \| grep 'Btrfs loaded'` must say `experimental=on`; else re-run `install.sh`. |
| `module verification failed: signature ... tainting kernel` | Module unsigned / MOK not enrolled. Harmless unless Secure Boot is enforced — then `mokutil --import /var/lib/dkms/mok.pub`. |
| `could not find kernel source for the '<x.y>' series` | Install it (`apt-get install linux-source-<x.y>`) or pass `KSRC=…`. |
| `ERROR: Kernel configuration is invalid` | Missing `linux-headers-$(uname -r)`. |
| Builds but won't load / undefined symbols | Kernel source series ≠ running kernel series. Pass `KSRC=` with the right tree. |
| New module installed but `lsmod` shows the old size | btrfs in use; unmount/`rmmod` first, or reboot. |

## Disclaimer

`raid-stripe-tree` is an **EXPERIMENTAL** kernel feature (it lives behind
`CONFIG_BTRFS_EXPERIMENTAL`, and `mkfs.btrfs` itself warns "do not use for
production"). Treat any filesystem using it accordingly and keep backups.
This repo only provides the kernel module; creating an RST filesystem
additionally requires a `btrfs-progs` built with `--enable-experimental` and
`mkfs.btrfs -O rst`.

## License

GPL-2.0 (the patch targets Linux kernel code; see `LICENSE`).
