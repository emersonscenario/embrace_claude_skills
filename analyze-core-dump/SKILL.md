---
name: analyze-core-dump
description: Use when an Embrace2 controller produced a core dump and needs analysis — symptoms include "Monitor crashed on the device", "I have a /data/coredumps/core.<exe>.<pid>.<sig>.<ts> file", "controller restarted unexpectedly with a coredump", or "produce a backtrace for review". Covers fetching the core, generating a module listing of running binaries, matching build-ids against ~/Embrace2_debug/.../.debug-registry.json, building a mapping dir, and running ~/Documentos/Recursos\ Embrace2/analisa-coredump.sh.
---

# analyze-core-dump

## Overview

Embrace2 produces standard Linux core dumps. The runtime binaries on the device are **stripped**, so analysis requires matching their GNU build-ids back to the corresponding `.debug` companions on the workstation. This skill walks through that match-and-analyze pipeline. It mirrors the `deploy-ac3` Java tool's logic and uses the same `analisa-coredump.sh` script so a CLI-only workflow gives the same results as the GUI.

EmbraceOS has **no journalctl** — runtime context comes from `dmesg`, `ServiceLogs`/`Logger`, and the core dump itself.

## When to use

- Device-side core present in `/data/coredumps/core.<exe>.<pid>.<sig>.<ts>` (e.g., `core.Embrace2Application.1234.11.1700000000`, `core.Dispatcher.612.11.1777915081`).
- User reports a crash, unexpected restart, WDT trip with a core captured, or asks for a backtrace they can attach to a bug report.
- Need to reproduce / validate a hypothesis from `dmesg` or smart logs against actual stack state.

When NOT to use:
- The crash signal is `SIGKILL` (9) — OOM-killer doesn't produce cores. Pivot to dmesg / cgroup memory traces (HARDWARE.md §8).
- The user only has logs, not a core.
- The crash happened on a debug build pushed to `/data/Firmware/` and the `.debug-registry.json` doesn't have those build-ids — see "When the build-id isn't in the registry" below.

## Inputs

You need three things:

1. **Core file** — fetched from `/data/coredumps/<name>` on the device.
2. **Module listing JSON** — describes which binaries were running with their build-ids. Generated either by the deploy-ac3 GUI or manually (see workflow). Identifies the monitor binary, all firmware module `.so`s in the *active* `/data/FirmwareA|B/`, and project items in the active `/data/ProjetoA|B/`.
3. **Debug directory** — local `~/Embrace2_debug/.../v<VERSION>/<ARCH>/` for the version that was running, ideally with a `.debug-registry.json` at its root.

## Workflow

### 1. Fetch the core

```bash
mkdir -p ~/analise
scp <user>@<device>:/data/coredumps/core.<exe>.<pid>.<sig>.<ts> ~/analise/
```

Decode the timestamp (last field):
```bash
date -d @<ts>
```

Cross-check with the device log to confirm version:
```bash
scp <user>@<device>:/LOGS/firmware_embrace.log ~/analise/
```

### 2. Generate the module listing

The listing is JSON containing the running binaries' build-ids so the analyzer can reconstruct the runtime symbol space.

**GUI route (recommended):** Use the deploy-ac3 Java tool (`~/Projects/deploy-ac3/`). `DebugRemoteService.generateModuleListing` connects via SSH/Shellhub, reads:

- `/home/scenario/embrace_monitor` — monitor binary build-id
- `/data/Configuracoes/ConfiguracoesFirmware.scj` — active firmware partition (`pastaExecucaoAtual` / `pastaExecucaoFirmware`); also `pastaNovaInstalacao` / `destinoNovoFirmware` for new-install dest
- `/data/Configuracoes/ConfiguracoesExecucaoProjeto.scj` — active project partition

It then `find`s every `.so` / `Embrace2Application*` / `embrace_monitor*` / executable file under the active firmware and project dirs, runs `readelf -n` on each (falling back to a local ARM `readelf` from `/opt/output-arm/host/bin/` over SCP, then to SHA-256), and writes `module-list-<controller>-<timestamp>.json`. The output schema:

```json
{
  "generatedAt": "2026-05-08T...",
  "target": "<ip-or-shellhub-tag>",
  "controllerId": "<mac-or-target>",
  "monitor": { "path": "/home/scenario/embrace_monitor",
               "version": "...", "buildId": "<hex>", "identity": "build-id:<hex>" },
  "firmware": { "version": "...", "executionFolder": "/data/FirmwareA",
                "items": [ { "path": "...", "name": "...", "identity": "build-id:<hex>", "buildId": "<hex>" } ] },
  "project":  { "version": "...", "executionFolder": "/data/ProjetoA",
                "items": [ { "path": "...", ... } ] }
}
```

Alternate-partition mode (`firmwareUseAlternate=true`, `projectUseAlternate=true`) scans `/data/FirmwareB` (or A) — useful when the partition was swapped after the crash.

**Manual route:** ssh to the device and run the equivalent commands by hand:

```bash
ssh <user>@<device> '
  cat /data/Configuracoes/ConfiguracoesFirmware.scj | jq -r .pastaExecucaoAtual,.pastaExecucaoFirmware
  readelf -n /home/scenario/embrace_monitor | grep "Build ID:"
  cd <active-partition>
  find . -type f \( -name "*.so" -o -name "Embrace2Application*" -o -name "embrace_monitor*" -o -perm -111 \) \
    -exec sh -c "echo {}: $(readelf -n {} | grep \"Build ID:\" | awk \"{print \\\$3}\")" \;
'
```

Build the JSON manually following the schema above.

### 3. Locate the debug directory

| Source | Path |
|---|---|
| Firmware release | `~/Embrace2_debug/Aplicacao/v<VERSION>/{ARM,x86}/` |
| Firmware branch-release | `~/Embrace2_debug/releases/Aplicacao/<branch>/{ARM,x86}/` |
| Monitor release | `~/Embrace2_debug/Monitor/v<VERSION>/{ARM,x86}/` |
| Monitor (via buildroot CI) | `~/Embrace2_debug/Monitor/os-v<VERSION>/{ARM,x86}/` |
| Monitor branch-release | `~/Embrace2_debug/releases/Monitor/<branch>/{ARM,x86}/` |

Each contains stripped binaries + matching `.debug` files + `.debug-registry.json`.

### 4. Match build-ids and build the mapping dir

The `.debug-registry.json` schema is tolerant — both forms accepted:

```json
{ "entries": [
    { "buildId": "abcdef…",  "path": "Embrace2Application" },
    { "buildId": "012345…",  "path": "lib/libCore.so" }
]}
```
or top-level array form. Field aliases handled by `CoreDumpAnalysisService.loadDebugIndexFromRegistry`:
- Build-id keys: `buildId` | `build_id` | `identity` (a leading `build-id:` prefix is stripped; comparison is lowercase)
- Path keys: `path` | `filePath` | `file` | `fullPath` (relative paths resolve against the debug dir)

For each entry in the listing's `monitor` + `firmware.items[]` + `project.items[]`, look up the build-id in the registry, then copy the binary to a mapping dir mirroring its device path:

```
mapping/
  home/scenario/embrace_monitor
  home/scenario/embrace_monitor.debug
  data/FirmwareA/lib/libCore.so
  data/FirmwareA/lib/libCore.so.debug
  ...
```

The `.debug` companion is found by `<binary>.debug` next to the source binary, or `<basename>.debug` in the same dir (matches `resolveDebugCompanion`). GDB's `.gnu_debuglink` resolves `.debug` siblings automatically.

When `.debug-registry.json` is **absent or empty**, fall back to walking the debug dir: index every `.so` / `Embrace2*` / executable file by `readelf -n` build-id and SHA-256 (mirrors `scanDebugDirectory`).

**Caching:** the deploy-ac3 service caches the mapping at `~/.deploy-ac3/debug-mapping/<controller>/<fingerprint>/` keyed on a SHA-256 of (listing contents + listing mtime + debug-dir path + registry mtime + layout `v3`). Invalidate with `CoreDumpAnalysisService.invalidateControllerCache(controllerId)` (or just `rm -rf ~/.deploy-ac3/debug-mapping/<controller>/`).

### 5. Run the analyzer

```bash
~/Documentos/Recursos\ Embrace2/analisa-coredump.sh \
    ~/analise/core.Embrace2Application.1234.11.1700000000 \
    /path/to/mapping
```

For batch / share-with-LLM output:
```bash
~/Documentos/Recursos\ Embrace2/analisa-coredump.sh \
    ~/analise/core.<...> \
    /path/to/mapping \
    --export ~/analise/<core>.gdb.txt
```

The script:
- Detects core architecture via `file <core>` → picks toolchain GDB:

  | Arch in core | GDB | Sysroot |
  |---|---|---|
  | ARM | `/opt/output-arm/host/bin/arm-buildroot-linux-gnueabihf-gdb` | `/opt/output-arm/host/arm-buildroot-linux-gnueabihf/sysroot` |
  | x86-64 | `/opt/output-x86/host/bin/x86_64-buildroot-linux-gnu-gdb` | `/opt/output-x86-full/host/x86_64-buildroot-linux-gnu/sysroot` |
  | x86-32 | same x86 GDB | same x86 sysroot |

- Locates the executable via `execfn:` from `file <core>` output (falls back to `core.<exe>.…`, finally interactive prompt).
- Builds `solib-search-path` recursively from every subdir of the mapping dir + sysroot lib dirs.
- Interactive mode drops you into GDB; `--export <file>` runs `info sharedlibrary` + `info threads` + `thread apply all bt full` + `info registers` and tees to a text file.

**NEVER use the system `gdb` or `gdb-multiarch`** — it doesn't know the Buildroot libc/libstdc++ ABI. The script enforces this.

## Triage from the GDB output

Read the **kill signal** from `info threads` (or just from the core file name — last `<sig>` field):

| Signal | Likely cause |
|---|---|
| **SIGSEGV (11)** | Null/UAF/buffer overflow / invalid memory access |
| **SIGABRT (6)** | `assert()` failed, `std::terminate()`, explicit `abort()`, uncaught exception |
| **SIGFPE (8)** | Divide-by-zero, FP overflow |
| **SIGBUS (7)** | Unaligned access (relevant on ARMv7) |
| **SIGILL (4)** | Corrupted code/stack, jumped into garbage |
| **SIGKILL (9)** | OOM-killer — **no core produced**; check `dmesg` for `Killed process` (HARDWARE.md §8) |

Then:
1. **Crashing thread** — read the topmost frames first; ignore frames inside libstdc++ unless they're the actual cause.
2. **All threads** — if the symptom was a hang / WDT trip, `thread apply all bt full` shows blocked threads (mutexes, condvars, syscalls).
3. **Stack corruption** — if backtraces are nonsense, check `info registers` and `x/10x $sp`.
4. **Connector / module symptoms** — look for frames in `Dispatcher`, `GerenciadorTimer`, `GerenciadorLinks`, `GerenciadorComunicacaoModular` (→ `firmware-module-communication`).

## When the build-id isn't in the registry

Common cases:

- **Debug build pushed via `deploy.sh`** to `/data/Firmware/` — the running binaries weren't built by CI, so no registry entry. Either (a) generate symbols locally with `~/Projects/aplicacao_ac/scripts/extract-debug-symbols.sh` against the `cmake-build-debug-banana/` dir and use that as the debug dir, or (b) repro the crash on a release build.
- **Active partition wasn't scanned** — listing was generated from the wrong partition; re-run with the `*UseAlternate` flag.
- **Wrong debug dir version** — listing shows version X but the chosen debug dir is for version Y. Check `~/Embrace2_debug/Aplicacao/v*/` and pick the one whose build-ids match.
- **Branch-release crash** — debug bundle is under `~/Embrace2_debug/releases/Aplicacao/<branch>/` rather than `Aplicacao/v<X>/`.

## Common failure modes

| Error | Cause / fix |
|---|---|
| `Executável '<name>' não encontrado em <debug-dir>` | Listing's build-id didn't match anything; verify version, partition, branch-release. |
| `no debug info found` for some `.so` | `.debug` companion missing → run `extract-debug-symbols.sh` for that build, or check `.gnu_debuglink` was preserved. |
| Backtrace shows only `??` | Wrong sysroot, or the binary isn't in the mapping dir. Check `solib-search-path` in GDB (`info sharedlibrary`). |
| Toolchain GDB not found | Buildroot output dir missing — re-run buildroot for the relevant arch (`embrace-buildroot`). |
| Core was truncated | `ulimit -c` or `kernel.core_pattern` on device — see HARDWARE.md §23. |
| `SIGKILL` core mentioned but no file exists | Correct: OOM-killer doesn't produce cores. Read dmesg. |

## Cross-references

- → `embrace-monitor` for which symptoms warrant a core analysis (WDT trips, hangs, ethernet-disconnect instability) and the `extract-debug-symbols.sh` location.
- → `embrace-firmware` for firmware crash hypotheses and the `gerarXSHX3.sh` packaging that produces `.xshx3` artifacts.
- → `firmware-module-communication` when the backtrace lives in `Dispatcher` / `GerenciadorTimer` / `GerenciadorLinks` / `GerenciadorComunicacaoModular`.
- → `embrace-buildroot` for the toolchain GDBs and sysroots.
- `~/Documentos/Recursos Embrace2/guia-coredump.md` — Portuguese user-facing guide; this skill is the working version.
- `~/Projects/deploy-ac3/src/main/java/br/ind/scenario/deploymonitor/service/debug/{CoreDumpAnalysisService,DebugRemoteService,DebugMappingCacheService,CoreDumpNaming}.java` — authoritative implementation of the listing + mapping flow.
