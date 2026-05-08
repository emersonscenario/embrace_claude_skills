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

## Prerequisites — local paths the skills assume

The skills reference concrete paths. Match the team layout or the recipes won't work:

| Path | What's there |
|---|---|
| `/opt/my-buildroot/` | Buildroot external tree |
| `/opt/output-x86-full/`, `/opt/output-x86-pro/`, `/opt/output-arm/` | Buildroot output dirs (host toolchain + sysroot) |
| `~/Projects/monitor/` | `embrace_monitor` repo |
| `~/Projects/aplicacao_ac/` | `embrace2` firmware repo |
| `~/IdeaProjects/AC3_Docs/` | MkDocs docs repo |
| `~/Embrace2/` | Release artifact dir (xmhx3, xshx3, Versionamento state) |
| `~/Embrace2_debug/` | Debug bundles (per-version + `.debug-registry.json`) |
| `~/Documentos/Recursos Embrace2/analisa-coredump.sh` | Core-dump analyzer script |
| `~/Projects/deploy-ac3/` | Java tool with the core-dump module-listing service |
| `192.168.10.66` (Banana Pi default) | Override per-call: `./deploy.sh <ip>` |

If your machine uses different paths, either (a) normalize to the team layout, or (b) keep a personal fork of these skills with paths sed-replaced.

## Install

Clone URLs:

- SSH (recommended for contributors): `git@github.com:emersonscenario/embrace_claude_skills.git`
- HTTPS (read-only / no SSH key): `https://github.com/emersonscenario/embrace_claude_skills.git`

The clone target dir name is up to you — examples below use `~/Projects/embrace-skills`. The directory name doesn't have to match the GitHub repo name.

### Option 1 — Global (recommended)

Every skill is available in every Claude Code session, regardless of `cwd`. Best for full-stack contributors who touch all four repos.

```bash
# Clone once
git clone git@github.com:emersonscenario/embrace_claude_skills.git ~/Projects/embrace-skills

# Symlink every skill into your personal Claude Code skills dir
mkdir -p ~/.claude/skills
for d in ~/Projects/embrace-skills/*/; do
    [ -f "$d/SKILL.md" ] || continue   # skip .git and any non-skill dirs
    ln -sfn "$d" ~/.claude/skills/"$(basename "$d")"
done
```

After this, `git pull` in `~/Projects/embrace-skills` updates everyone's symlinks instantly — no relink step.

### Option 2 — Per-repo (scope skills to one project)

Each repo gets only its relevant skills, dropped into its `.claude/skills/`. Skills auto-load only when `claude` runs from inside that repo's tree. Best for contributors who only work on one component.

```bash
git clone git@github.com:emersonscenario/embrace_claude_skills.git ~/Projects/embrace-skills

# Buildroot only
mkdir -p /opt/my-buildroot/.claude/skills
for s in embrace-buildroot analyze-core-dump embrace-docs; do
    ln -sfn ~/Projects/embrace-skills/$s /opt/my-buildroot/.claude/skills/$s
done

# Monitor only
mkdir -p ~/Projects/monitor/.claude/skills
for s in embrace-monitor analyze-core-dump embrace-docs; do
    ln -sfn ~/Projects/embrace-skills/$s ~/Projects/monitor/.claude/skills/$s
done

# Firmware only
mkdir -p ~/Projects/aplicacao_ac/.claude/skills
for s in embrace-firmware add-firmware-module firmware-module-communication analyze-core-dump embrace-docs; do
    ln -sfn ~/Projects/embrace-skills/$s ~/Projects/aplicacao_ac/.claude/skills/$s
done

# Docs only
mkdir -p ~/IdeaProjects/AC3_Docs/.claude/skills
ln -sfn ~/Projects/embrace-skills/embrace-docs ~/IdeaProjects/AC3_Docs/.claude/skills/embrace-docs
```

Add `.claude/skills/` to each repo's `.gitignore` if you don't want the symlinks committed (they're machine-local).

### Option 3 — Selective global

Pick a subset of skills and symlink only those into `~/.claude/skills/`. Useful if a teammate only wants, say, `analyze-core-dump` and `embrace-docs` without seeing the firmware/monitor/buildroot mega-skills in their session start.

```bash
git clone git@github.com:emersonscenario/embrace_claude_skills.git ~/Projects/embrace-skills
mkdir -p ~/.claude/skills

for s in analyze-core-dump embrace-docs; do
    ln -sfn ~/Projects/embrace-skills/$s ~/.claude/skills/$s
done
```

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
```

Symlinks resolve through the repo, so the next Claude Code session picks up the changes. No re-symlink needed.

If you've added new skills since the last sync, re-run the symlink loop from your install option to pick them up.

## Uninstall

```bash
# Global
find ~/.claude/skills -maxdepth 1 -type l -lname '*embrace-skills*' -delete

# Per-repo
find <repo>/.claude/skills -maxdepth 1 -type l -lname '*embrace-skills*' -delete
```

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
