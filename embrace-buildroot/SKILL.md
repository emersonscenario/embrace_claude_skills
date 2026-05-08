---
name: embrace-buildroot
description: Use when working in /opt/my-buildroot/ or on EmbraceOS Buildroot — the 3 board variants (x86_full, x86_pro, ARM Banana Pi Zero 2), RAUC A/B boot with grubenv, .xmhx3 installer artifacts, GRUB ESP, defconfigs, kernel options, rootfs overlays, GitHub Actions on the ac3-overlay self-hosted runner, EmbraceOS versioning, gera-iso-x86.sh / atualiza-banana-img.sh / provision-device.sh.
---

# embrace-buildroot

## Overview

External Buildroot tree for EmbraceOS. Builds 3 variants of a Linux image with RAUC A/B rootfs, GRUB EFI (x86) or U-Boot (ARM), and packages each into a versioned `.xmhx3` installer. CI runs on the `ac3-overlay` self-hosted GitHub Actions runner. EmbraceOS does **not** ship `journalctl` — debug paths use `dmesg` + ServiceLogs/Logger + core dumps.

## Variant matrix

| Variant | Defconfig | Output dir | RAUC `compatible` | Artifact |
|---|---|---|---|---|
| `x86_full` | `x86_full_defconfig` | `/opt/output-x86-full/` | `EmbraceOS-x86-full` | `EmbraceOS_x86_full_v<X.Y.Z.W>.xmhx3` |
| `x86_pro` | `x86_pro_defconfig` | `/opt/output-x86-pro/` | `EmbraceOS-x86-pro` | `EmbraceOS_x86_pro_v<X.Y.Z.W>.xmhx3` |
| ARM (BananaPi Zero 2) | `mybpip2zero_defconfig` | `/opt/output-arm/` | `EB-AC3` | `EmbraceOS_ARM32_v<X.Y.Z.W>.xmhx3` |

Promotion: `~/Embrace2/` (current) + `~/Embrace2/Anteriores/` (last 5 retained).

## Build commands

```bash
# Configure once per variant
make O=/opt/output-x86-full BR2_EXTERNAL=/opt/my-buildroot x86_full_defconfig
make O=/opt/output-x86-pro  BR2_EXTERNAL=/opt/my-buildroot x86_pro_defconfig
make O=/opt/output-arm      BR2_EXTERNAL=/opt/my-buildroot mybpip2zero_defconfig

# Build
make O=/opt/output-x86-full -j$(nproc)

# menuconfig / linux-menuconfig
make O=/opt/output-x86-full menuconfig
make O=/opt/output-x86-full linux-menuconfig

# Save defconfig back to repo
make O=/opt/output-x86-full savedefconfig BR2_DEFCONFIG=/opt/my-buildroot/configs/x86_full_defconfig
make O=/opt/output-x86-full linux-update-defconfig

# Per-package (requires that variant be configured first)
make O=/opt/output-x86-full <package>-rebuild
make O=/opt/output-x86-full <package>-dirclean

# Full reset
make O=/opt/output-x86-full distclean
```

## RAUC A/B model (x86)

Initial state set by `board/myx86/post-image_rauc.sh`:
```
ORDER="rootfs0 rootfs1"
rootfs0_OK=1   rootfs0_TRY=0    # primary, healthy
rootfs1_OK=0   rootfs1_TRY=0    # spare, awaiting first install
```
- `*_TRY` increments each boot attempt; reset to 0 on confirmed-good (`rauc status mark-good`).
- `*_OK` flips when an install completes; `ORDER` is rotated by RAUC's grub2 backend.
- `grubenv` location on disk: `/boot/EFI/BOOT/grubenv` (read/write by GRUB).
- `grub.cfg` is **static** at `board/myx86/grub.cfg` — single source of truth, copied into the ESP.
- RAUC system config per variant: `board/x86_full/overlay/etc/rauc/system.conf`, `board/x86_pro/overlay/etc/rauc/system.conf`. ARM uses `board/mybpip2zero/`.

ARM uses a similar A/B pattern via U-Boot — see `board/mybpip2zero/`.

## Artifact pipeline (`post-image_rauc.sh`)

Buildroot calls this once per variant. It produces both bundles + `.xmhx3`:

1. **EFI scaffolding:** `BOOTX64.EFI` ← `grubx64.efi`; static `grub.cfg`; initial `grubenv`.
2. **`boot.vfat`** via `genimage --config genbootfs.cfg` (1st pass, no rootpath data).
3. **`update.raucb`** (boot + rootfs): manifest + `boot.vfat` + `rootfs.squashfs`, signed with `RAUC_CERT`/`RAUC_KEY`/`RAUC_KEYRING`.
4. **`rootfs.raucb`** (rootfs-only, used as the installer payload).
5. **`rauc.status`** generated from the bundle's manifest digest, installed into `/data/rauc.status` and `/LOGS/rauc.status`.
6. **`disk.img`** via `genimage --config genimage_rauc.cfg` (2nd pass, with rootpath including `rauc.status`, `authorized_keys`, `Dependencias/`).
7. **`disk.img.bmap`** (`bmaptool`) + **`disk.img.lz4`** for fast flashing.
8. **`geraXMHX3.sh`** packages `rootfs.raucb` + `info.ini` + `FontesMD5.txt` into `EmbraceOS_<VARIANT>_v<VERSION>.xmhx3` (a zip), placed in `${EMBRACE2_XMHX3_OUTPUT_DIR:-~/Embrace2}/`.

Variant selection in `geraXMHX3.sh`: `EMBRACE2_BOARD_VARIANT` (`x86_full` | `x86_pro` | `x86`); `EMBRACE2_RAUC_COMPATIBLE`.

## Versioning (`Versionamento/EmbraceOSVersion.sh`)

Format: `MAJOR.MINOR.PATCH.BUILD`. Developer manages M.m.P in `board/myx86/rootfs_overlay_rauc/usr/lib/os-release` (and ARM equivalent). Build (W) auto-increments per push.

```bash
# Auto-increment (used by CI)
bash Versionamento/EmbraceOSVersion.sh x86 /opt/my-buildroot
bash Versionamento/EmbraceOSVersion.sh ARM /opt/my-buildroot

# Force exact version (production release)
EMBRACE2_RELEASE_VERSION=1.2.3.0 bash Versionamento/EmbraceOSVersion.sh x86
```

State files (runner-local, persist between runs):
- `~/Embrace2/Versionamento/embraceos_x86.txt`
- `~/Embrace2/Versionamento/embraceos_ARM.txt`

Build resets to 1 when M.m.P changes in `os-release`.

The script also patches `os-release` (`VERSION_ID`, `VERSION`, `PRETTY_NAME`).

## CI/CD (release.yml)

Runner: `[self-hosted, linux, x64, ac3-overlay]`. Triggers: `push: main` + `workflow_dispatch` with `release_type` choice (`prerelease` | `production`).

**Stage 1 — `validate-configs` (5 min):**
- Defconfigs must define `BR2_TARGET_GENERIC_HOSTNAME`.
- Scan `git ls-files` for `*.key.pem` (committed private keys → fail).

**Stage 2 — `full-linux-build` (120 min, depends on validate):**

1. Prepare staging dir at `/tmp/embrace2-staging-embraceos-${RUN_ID}-${ATTEMPT}`; compute `CORES_PER_BUILD = max(2, (nproc - 4) / 3)`.
2. Determine version: tag `v*` → exact; else suffix `_pre_release` unless `release_type=production`.
3. Auto-increment x86 + ARM versions via `Versionamento/EmbraceOSVersion.sh`.
4. Restore RAUC keys from `secrets.RAUC_{CA_CERT,DEV_CERT,DEV_KEY}` (or local `~/.embrace2/rauc-keys/` fallback) into `board/{mybpip2zero,myx86}/openssl-ca/dev/`.
5. **Migrate** `/opt/output-x86` → `/opt/output-x86-full` (one-time, with symlink); bootstrap `/opt/output-x86-pro` from x86-full via `cp -al`.
6. **Clone monitor** at `${RUNNER_TEMP}/ac3_monitor` from `git@github.com:scenarioautomation/ac3_monitor.git --depth=1 --branch=main`. **The monitor is NOT a Buildroot submodule.**
7. **Build monitor x86 Release** with `/opt/output-x86-full/host/share/buildroot/toolchainfile.cmake`; run `extract-debug-symbols.sh`. Copy:
   - `embrace_monitor` → `board/myx86/rootfs_overlay_rauc/home/scenario/embrace_monitor`
   - `liblogserviceapi.so` (ServiceLogs), `libgpio_client.so` (DriverGPIO) → `usr/lib/`
8. **Build frontend** (Angular, `npx ng build --configuration=production`) → `opt/monitor/www/`.
9. **Build monitor ARM Release** + same overlay deploy under `board/mybpip2zero/rootfs_overlay_rauc/`.
10. **Seed FirmwareA + FirmwareB** in both overlays from the latest `~/Embrace2/EB-AC_v*_Slim.xshx3` (ARM) and `EB-AC_v*_Full_Pro.xshx3` (x86). **Both A and B are seeded with the SAME firmware** at install time. The firmware itself is NOT built here — it comes from the firmware repo's release pipeline.
11. **Buildroot builds:** ARM in parallel; **x86_full → x86_pro sequential** because the x86_pro kernel state is refreshed from x86_full via `cp -al` (hard-linked) plus `sed -i` to fix paths inside `*.cmd`. `flock` per output dir prevents concurrent runs.
12. **Locate artifacts:** find `.xmhx3` in staging; if pre-release, rename with `_pre_release` suffix.
13. **Promote:** rotate current `~/Embrace2/EmbraceOS_*.xmhx3` → `~/Embrace2/Anteriores/`; prune to last 5 per variant; move new artifacts in.
14. **Cleanup on failure** removes staging + log dirs.

Other workflows: `validate.yml` (PR check, same checks as Stage 1), `branch-release.yml` (dispatch-only, any branch), `create-tag.yml` (promote latest pre-release to tag).

## Adding a Buildroot package

External-tree pattern under `package/<name>/` with `Config.in` + `<name>.mk`. Then:
1. Add `source "$(BR2_EXTERNAL_my_buildroot_PATH)/package/<name>/Config.in"` to `Config.in` at root (or under a sub-menu).
2. Enable `BR2_PACKAGE_<NAME>=y` in the relevant defconfig(s).
3. Save with `make O=... savedefconfig BR2_DEFCONFIG=configs/<name>_defconfig`.
4. Rebuild: `make O=... <name>-rebuild`.

For ARM-only or x86-only: add to one defconfig only.

## Modifying the kernel

```bash
make O=/opt/output-x86-full linux-menuconfig
# select the option, exit & save
make O=/opt/output-x86-full linux-update-defconfig
# This writes the changed defconfig back to .config; copy to /opt/my-buildroot/board/<variant>/linux.config
```

For a new driver / module: enable as `=m` (module) or `=y` (built-in). If `=m`, ensure the module is loaded (rootfs overlay's `/etc/modules-load.d/`).

## Rootfs overlays

| Overlay | Purpose |
|---|---|
| `board/myx86/rootfs_overlay_rauc/` | Common x86 overlay — embrace_monitor, frontend, ServiceLogs / GPIO libs, os-release, /data/.ssh keys, Dependencias/ |
| `board/x86_full/overlay/` | x86_full-specific (RAUC system.conf with `EmbraceOS-x86-full`) |
| `board/x86_pro/overlay/` | x86_pro-specific (RAUC system.conf with `EmbraceOS-x86-pro` + DHCP server config) |
| `board/mybpip2zero/rootfs_overlay_rauc/` | ARM overlay — embrace_monitor, frontend, libs |

## Local-flow scripts

```bash
# Generate Debian-live install ISOs (x86)
./scripts/gera-iso-x86.sh \
    --full /opt/output-x86-full/images/disk.img.lz4 \
    --pro  /opt/output-x86-pro/images/disk.img.lz4 \
    --output ~/Documentos/Recursos\ Embrace2/

# Update Banana Pi installer image (uses bmaptool, requires sudo)
./scripts/atualiza-banana-img.sh \
    --img ~/Documentos/Recursos\ Embrace2/Imagem\ Banana\ Auto.img \
    --sdcard /opt/output-arm/images/disk.img \
    --output ~/Documentos/Recursos\ Embrace2/

# Provision a device for development
./scripts/provision-device.sh
```

## Failure cookbook

| Symptom | Where to look |
|---|---|
| Validate fails on hostname | `configs/<variant>_defconfig` missing `BR2_TARGET_GENERIC_HOSTNAME=...` |
| Validate fails on private key | `git ls-files \| grep '\.key\.pem$'` — purge with `git rm --cached` + history rewrite |
| RAUC bundle not produced | `post-image_rauc.sh` step — check `BINARIES_DIR/{boot.vfat,rootfs.squashfs}` exist, certs present, `host/bin/rauc` works |
| `.xmhx3` not found in staging | `geraXMHX3.sh` failure — check `EMBRACE2_BOARD_VARIANT` set, `EMBRACE2_XMHX3_OUTPUT_DIR` writable |
| Version not bumping | Inspect `~/Embrace2/Versionamento/embraceos_<arch>.txt`; mismatch with `os-release` resets build to 1 |
| Wrong version | Set `EMBRACE2_RELEASE_VERSION=X.Y.Z.W` |
| GRUB doesn't boot after install | `grub-editenv /boot/EFI/BOOT/grubenv list` on device — check `ORDER`, `*_OK`, `*_TRY` |
| Boot loops to other slot | `*_TRY` exceeded threshold; healthy boot must call `rauc status mark-good` |
| `cp -al` failed for x86_pro | x86_full and x86_pro must share a kernel-version dir; if x86_full was rebuilt with a new kernel, x86_pro state is regenerated |
| ARM build hangs | Check `flock /tmp/embrace2-buildroot-arm.lock` — another build holds it |
| Monitor outdated in image | `Clone Monitor Source` step pulls `main`; pin a specific commit/branch in workflow if needed |
| FirmwareA/B empty | No `EB-AC_v*_{Slim,Full_Pro}.xshx3` in `~/Embrace2/` — run firmware release first or copy artifact in |
| RAUC keys missing | Set `secrets.RAUC_{CA_CERT,DEV_CERT,DEV_KEY}` in GitHub OR populate `~/.embrace2/rauc-keys/` on the runner |
| Runner offline | GitHub UI → Actions → Runners → confirm `ac3-overlay` is listed; check the runner host service |

Runtime debugging on the resulting OS image: **no journalctl** — use `dmesg` + the apps' own logs.

## Cross-references

- → `embrace-monitor` for the monitor binary that ends up in `rootfs_overlay_rauc/home/scenario/`.
- → `embrace-firmware` for the firmware whose `.xshx3` the CI seeds into FirmwareA/B; firmware/monitor CI consume `/opt/output-*/host/share/buildroot/toolchainfile.cmake` produced by buildroot here.
- → `embrace-docs` for updating `Embrace2/CICD/` and `Embrace2/Arquitetura Embrace2.md` after pipeline changes.
- → `analyze-core-dump` when a core from a CI smoke test or the resulting OS lands.
- `AC3_Docs/Hardware/HARDWARE.md` for the ARM target's hardware constraints.
- `AC3_Docs/Embrace2/CICD/` for the design docs of the pipeline.
