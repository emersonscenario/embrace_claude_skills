# embrace-skills

Repository: <https://github.com/emersonscenario/embrace_claude_skills>

Seven Claude Code skills that capture the EmbraceOS ecosystem (Buildroot OS image, `embrace_monitor` daemon, `embrace2` firmware, AC3_Docs documentation site, plus shared workflows). They give Claude the tacit knowledge a new contributor would otherwise spend weeks rediscovering: A/B partition layout, no-`journalctl` debug ladders, the `Dispatcher` / `GerenciadorTimer` / `GerenciadorLinks` / `GerenciadorComunicacaoModular` model, the build-id → `.debug-registry.json` core-dump pipeline, the buildroot CI pipeline, etc.

## What's inside

| Skill | Trigger style | What it covers |
|---|---|---|
| `embrace-buildroot` | Auto | `/opt/my-buildroot/`, RAUC A/B, 3 board variants, `.xmhx3` artifacts, GitHub Actions on `ac3-overlay`, `Versionamento/EmbraceOSVersion.sh`, kernel/defconfig changes, rootfs overlays |
| `embrace-monitor` | Auto | `~/Projects/monitor/`, `MonitorFirmware`, WDT pulse, `ConexaoFirmware` TCP/Unix-socket protocol, RAUC OTA, Cloud token + WebSocket, `ConfigWebAPI` mongoose backend, ServiceLogs, core-dump generation hooks |
| `embrace-firmware` | Auto | `~/Projects/aplicacao_ac/`, module taxonomy (50+ modules), `Bibliotecas/` library layer, `deploy.sh` debug push vs A/B production, smart logs, runtime debug procedures |
| `firmware-module-communication` | Auto | The four singletons (`Dispatcher`, `GerenciadorTimer`, `GerenciadorLinks`, `GerenciadorComunicacaoModular`), connector-vs-link distinction, `/LOGS/debugDispatcher.txt`, the 9-step "module A isn't reacting to B" debug ladder |
| `add-firmware-module` | Auto | Scaffolding a new module: file layout, class skeleton, CMake registration, the per-module triplet (connectors / timers / modular payload), test scaffold, docs entry |
| `analyze-core-dump` | Auto | `/data/coredumps/` → module listing → `.debug-registry.json` → mapping dir → `analisa-coredump.sh` (toolchain GDB, never system gdb) |
| `embrace-docs` | **Manual only** (`/embrace-docs`) | Sync `~/IdeaProjects/AC3_Docs/` after committing in any of the 3 source repos. Won't auto-fire. |

"Auto" = Claude reads each skill's `description` at session start and decides per turn whether to load the body. "Manual only" = wait for explicit `/skill-name` invocation.

## Path configuration

The skills are templates rendered to literal paths at install time. The team
defaults live in `paths.defaults.conf` (committed). To use a different layout,
copy `paths.conf.example` to `~/.config/embrace-skills/paths.conf` (or
`<repo>/paths.local.conf`) and uncomment the variables you want to override —
unset variables inherit from the defaults.

| Variable | Default | What it points to |
|---|---|---|
| `BUILDROOT_DIR` | `/opt/my-buildroot` | Buildroot external tree |
| `BUILDROOT_OUT_X86_FULL` | `/opt/output-x86-full` | x86 full output dir |
| `BUILDROOT_OUT_X86_PRO`  | `/opt/output-x86-pro`  | x86 pro output dir |
| `BUILDROOT_OUT_ARM`      | `/opt/output-arm`      | ARM output dir |
| `MONITOR_DIR`            | `~/Projects/monitor`        | `embrace_monitor` repo |
| `FIRMWARE_DIR`           | `~/Projects/aplicacao_ac`   | `embrace2` firmware repo |
| `DEPLOY_AC3_DIR`         | `~/Projects/deploy-ac3`     | Deploy tool repo |
| `DOCS_DIR`               | `~/IdeaProjects/AC3_Docs`   | MkDocs docs repo |
| `EMBRACE2_DIR`           | `~/Embrace2`                | Release artefact dir |
| `EMBRACE2_DEBUG_DIR`     | `~/Embrace2_debug`          | Debug bundles dir |
| `RECURSOS_DIR`           | `~/Documentos/Recursos Embrace2` | Banana Pi base image + provisioning output |

The device IP is **not configured here.** Skills that need device access prompt
for `<DEVICE_IP>` per invocation; if you don't supply one, the skill halts.

## Install

```bash
# Clone once
git clone git@github.com:emersonscenario/embrace_claude_skills.git ~/Projects/embrace-skills
cd ~/Projects/embrace-skills

# (optional) override paths
mkdir -p ~/.config/embrace-skills
cp paths.conf.example ~/.config/embrace-skills/paths.conf
$EDITOR ~/.config/embrace-skills/paths.conf

# install (default: global mode)
./install.sh
```

Modes:

- `./install.sh --mode=global` (default) — symlinks every rendered skill into `~/.claude/skills/`. Best for full-stack contributors.
- `./install.sh --mode=per-repo` — symlinks scoped subsets into each target repo's `.claude/skills/`:
  - `$BUILDROOT_DIR/.claude/skills/`: `embrace-buildroot`, `analyze-core-dump`, `embrace-docs`
  - `$MONITOR_DIR/.claude/skills/`: `embrace-monitor`, `analyze-core-dump`, `embrace-docs`
  - `$FIRMWARE_DIR/.claude/skills/`: `embrace-firmware`, `add-firmware-module`, `firmware-module-communication`, `analyze-core-dump`, `embrace-docs`
  - `$DOCS_DIR/.claude/skills/`: `embrace-docs`

## Verify

```bash
ls -l ~/.claude/skills/                     # for global install
ls -l <repo>/.claude/skills/                # for per-repo install
```

Open a new Claude Code session and ask `/skills` or list available skills — the embrace skills should appear by name. If a skill is missing:

- Confirm `SKILL.md` exists inside the symlinked directory: `cat ~/.claude/skills/embrace-buildroot/SKILL.md | head -5`.
- Restart `claude` (the index loads at session start, not on file change).
- For per-repo skills: confirm your `cwd` is inside the repo when starting `claude`.

## Usage

Most skills fire automatically based on their `description` field — Claude decides per turn which to invoke based on what you're doing. You don't list them.

```
$ cd ~/Projects/aplicacao_ac
$ claude
> Why isn't my Lampada reacting to the Pulsador?
# Claude auto-loads embrace-firmware + firmware-module-communication
# and walks the 7-step ladder in the latter.
```

Manual invocation with `/skill-name` overrides this and forces a specific skill to load:

```
> /embrace-docs
# Pulls recent commits across the 3 source repos and proposes doc edits.
> /analyze-core-dump
# Walks you through fetching the core, generating the listing, etc.
```

`embrace-docs` is **manual only** by design — its description has an explicit anti-trigger so Claude won't fire it automatically when you happen to be working near doc files.

## Updates

```bash
cd ~/Projects/embrace-skills
git pull
./install.sh --render-only
```

If you edited `~/.config/embrace-skills/paths.conf`, run `./install.sh --reconfigure` instead — same effect, clearer in command history.

## Uninstall

```bash
cd ~/Projects/embrace-skills
./uninstall.sh                  # default: global
./uninstall.sh --mode=per-repo  # if you installed with --mode=per-repo
```

This only removes symlinks pointing at `.rendered/` under this repo — unrelated symlinks in `~/.claude/skills/` are left alone.

## Contributing

The skills evolve as the codebase does. When updating:

1. Edit the relevant `SKILL.md`.
2. Keep the `description` frontmatter to triggering conditions only — never summarize the skill's workflow there (Claude will follow the description and skip the body).
3. Quote source paths verbatim. Skills should reference `Core/Dispatcher.h`, not "the dispatcher class".
4. After a notable behavior change in any of the source repos, sync the relevant skill alongside the AC3_Docs page (use `/embrace-docs` for the docs side).
5. Commit + push. Teammates' next `git pull` picks it up.

The internal design spec for the skill set lives in `~/IdeaProjects/AC3_Docs/docs/superpowers/specs/2026-05-08-embrace-skills-design.md`.

## License

Internal — Scenario / Embrace team only.
