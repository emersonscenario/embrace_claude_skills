# Configurable paths for embrace-skills

**Date:** 2026-05-11
**Status:** Approved (brainstorming → ready for implementation plan)
**Repo:** `~/Projects/embrace-skills` (`embrace-skills` on GitHub)
**Author:** Emerson Voltarelli (collaborated with Claude)

## Problem

Every `SKILL.md` in the repo embeds the team's host layout literally:
`/opt/my-buildroot`, `/opt/output-x86-full`, `/opt/output-x86-pro`, `/opt/output-arm`,
`~/Projects/monitor`, `~/Projects/aplicacao_ac`, `~/Projects/deploy-ac3`,
`~/IdeaProjects/AC3_Docs`, `~/Embrace2`, `~/Embrace2_debug`,
`~/Documentos/Recursos Embrace2`, plus the dev device IP `192.168.10.66`.

Across 7 SKILL.md files that's ~85 occurrences of those values. The current README
solution — "normalize to the team layout or keep a personal fork with paths
sed-replaced" — pushes the cost onto every contributor whose machine differs and
makes `git pull` updates manual to rebase.

## Goal

Let each contributor configure host-machine paths once in a local file, with the
team defaults committed. The body Claude sees when a skill is invoked must contain
**literal paths** (not unexpanded `${VAR}` tokens or runtime lookup instructions)
so session-token cost stays identical to today and Claude cannot accidentally
emit an unresolved placeholder into a shell command.

## Non-goals

- Parametrizing device-side EmbraceOS paths (`/data/Firmware*`, `/data/Projeto*`,
  `/data/Configuracoes/*.scj`, `/data/coredumps/`, `/data/rauc.status`, `/LOGS/*`,
  `/opt/monitor/www/`). These are kernel/firmware contracts inside the OS image;
  changing them means changing EmbraceOS, not a per-developer setting.
- Providing a default device IP. If a skill needs device access and the user
  didn't supply an IP, the skill halts and asks. No `192.168.10.66` fallback.
- A live "watch + auto-render" daemon. Re-render is an explicit step paired with
  `git pull` or `paths.conf` edits.

## Approach: render at install

Skills become templates. An `install.sh` reads layered config files, substitutes
`{{VAR_NAME}}` tokens, and writes the rendered `SKILL.md` to a per-user output
tree. The `~/.claude/skills/<name>` symlinks point at that rendered tree, so
Claude reads literal paths.

This was chosen over two rejected alternatives:

- **Runtime preamble + paths.conf lookup at use time.** Forces every invocation
  to (a) load the conf, (b) substitute tokens mentally on every path mention.
  Highest session-token cost; high risk of `${VAR}` leaking into a copy-pasted
  command. Rejected.
- **Env vars + preamble "prefer `$VAR` over literal".** No render step but skill
  bodies grow a preamble, and Claude has to remember to apply the override on
  every path occurrence. Rejected — accuracy cost not worth saving the render
  step.

## Variables

11 host-machine paths. Shell-source-compatible so `install.sh` can `source` them
directly.

```sh
# paths.defaults.conf  (committed, team layout)
BUILDROOT_DIR="/opt/my-buildroot"
BUILDROOT_OUT_X86_FULL="/opt/output-x86-full"
BUILDROOT_OUT_X86_PRO="/opt/output-x86-pro"
BUILDROOT_OUT_ARM="/opt/output-arm"
MONITOR_DIR="$HOME/Projects/monitor"
FIRMWARE_DIR="$HOME/Projects/aplicacao_ac"
DEPLOY_AC3_DIR="$HOME/Projects/deploy-ac3"
DOCS_DIR="$HOME/IdeaProjects/AC3_Docs"
EMBRACE2_DIR="$HOME/Embrace2"
EMBRACE2_DEBUG_DIR="$HOME/Embrace2_debug"
RECURSOS_DIR="$HOME/Documentos/Recursos Embrace2"
```

User overrides go in `~/.config/embrace-skills/paths.conf` (or
`<repo>/paths.local.conf`, gitignored). The override file contains only values
that differ from defaults; missing keys inherit from defaults.

In addition, the renderer exposes one implicit variable:

- `{{SKILLS_REPO}}` — absolute path to this repo, so templates can reference
  bundled resources without the user configuring it.

### Things deliberately removed

- `BUILDROOT_OUT_X86_LEGACY` (`/opt/output-x86`) — the historical pre-split x86
  output dir. The one remaining reference in `analyze-core-dump/SKILL.md:159`
  (the x86_64 gdb path) was already stale; it gets corrected to
  `{{BUILDROOT_OUT_X86_FULL}}/host/bin/x86_64-buildroot-linux-gnu-gdb`. The
  one-time migration note in `embrace-buildroot/SKILL.md:115` is deleted.
- `~/Documentos/Recursos Embrace2/analisa-coredump.sh` — moves into the repo at
  `resources/analisa-coredump.sh`. Skill body references it as
  `{{SKILLS_REPO}}/resources/analisa-coredump.sh`. No longer a config concern.
- `~/Documentos/Recursos Embrace2/guia-coredump.md` — moves into the repo at
  `resources/guia-coredump.md` for the same reason.
- `192.168.10.66` / `192.168.10.42` — removed. Skills that need a device IP say
  "ask the user for `<DEVICE_IP>`; halt if not provided".

`RECURSOS_DIR` is kept (not deleted) because the buildroot skill still
references it for `Imagem Banana Auto.img` (a large binary asset) and as the
`--output` dir for `gera-iso-x86.sh` / `atualiza-banana-img.sh` — those are
working directories on the user's machine, not bundle-able artifacts.

## Repo layout after change

```
embrace-skills/
├── README.md                     (updated — new install + update flow)
├── paths.defaults.conf           NEW
├── paths.conf.example            NEW (annotated)
├── install.sh                    NEW
├── uninstall.sh                  NEW
├── lib/
│   └── render.sh                 NEW (pure-bash {{VAR}} substitution)
├── resources/                    NEW
│   ├── analisa-coredump.sh
│   └── guia-coredump.md
├── .rendered/                    GITIGNORED — per-user render output
│   └── <skill>/SKILL.md
├── add-firmware-module/
│   └── SKILL.md.tmpl             was SKILL.md
├── analyze-core-dump/
│   └── SKILL.md.tmpl
├── embrace-buildroot/
│   └── SKILL.md.tmpl
├── embrace-docs/
│   └── SKILL.md.tmpl
├── embrace-firmware/
│   └── SKILL.md.tmpl
├── embrace-monitor/
│   └── SKILL.md.tmpl
├── firmware-module-communication/
│   └── SKILL.md.tmpl
└── .gitignore                    adds /.rendered/, paths.conf, paths.local.conf
```

### Template syntax

`{{VAR_NAME}}` for all 11 path variables plus `{{SKILLS_REPO}}`. No other
templating features. Render is a single regex pass per template.

Quoting rule: in template prose, variable references appear bare
(`{{FIRMWARE_DIR}}/Core/`). In shell snippets meant to be copy-pasted, the
renderer outputs literal paths and the snippet is responsible for any quoting
needed (relevant for `RECURSOS_DIR`, which has a space).

## `install.sh` interface

```
./install.sh [--mode=global|per-repo] [--render-only] [--reconfigure]
```

### Flow

1. **Load config**: `source paths.defaults.conf`. Then if
   `~/.config/embrace-skills/paths.conf` exists, source it. Then if
   `./paths.local.conf` exists, source it (repo-local override wins for the
   per-repo case).
2. **Validate**: for each variable, check the directory exists. Missing dirs
   produce a warning, not a hard fail — a contributor who only works on
   firmware shouldn't be blocked by an absent buildroot tree.
3. **Render**: for each `<skill>/SKILL.md.tmpl`, substitute `{{VAR_NAME}}` →
   value, write to `.rendered/<skill>/SKILL.md`. Set `{{SKILLS_REPO}}` to the
   absolute path of the repo.
4. **Symlink**:
   - `--mode=global` (default): `~/.claude/skills/<name>` →
     `<repo>/.rendered/<name>/`.
   - `--mode=per-repo`: applies the existing README option-2 mapping —
     `{{BUILDROOT_DIR}}/.claude/skills/` gets buildroot + core-dump + docs;
     `{{MONITOR_DIR}}/.claude/skills/` gets monitor + core-dump + docs;
     `{{FIRMWARE_DIR}}/.claude/skills/` gets firmware + add-module +
     module-comm + core-dump + docs; `{{DOCS_DIR}}/.claude/skills/` gets docs.
     Symlink targets are all `<repo>/.rendered/<name>/`.
5. **Flags**:
   - `--render-only`: skip steps 4 (no symlinking). Used after `git pull` or
     after editing `paths.conf`.
   - `--reconfigure`: alias for `--render-only` with explicit "I edited the
     conf" intent (same behavior; clearer in command history).

### `uninstall.sh` interface

```
./uninstall.sh [--mode=global|per-repo]
```

Removes the symlinks created by `install.sh` (uses `find -maxdepth 1 -type l
-lname '*embrace-skills*' -delete`, same pattern the README already documents).
Does not delete `.rendered/` or the user's `paths.conf`.

## Token / session cost

After render, each `~/.claude/skills/<name>/SKILL.md` is literal text identical
in shape to today's `SKILL.md`. No preamble added, no runtime conf lookup, no
mental substitution. **Body tokens delivered to Claude on skill invocation =
unchanged from today.** Prompt-cache behavior unchanged.

The only token addition is the `<DEVICE_IP>` wording change in the two skills
that touch the Banana Pi (`embrace-firmware`, `embrace-monitor`) — net ~10–20
tokens per skill. Negligible.

## Per-skill body changes

These are the only text edits to the skill content itself (everything else is
mechanical `path → {{VAR}}` substitution during the template conversion):

1. **`embrace-buildroot/SKILL.md.tmpl`**
   - Delete the line "Migrate `/opt/output-x86` → `/opt/output-x86-full`
     (one-time, with symlink); bootstrap `/opt/output-x86-pro` from x86-full
     via `cp -al`." (currently line 115). One-time migration that's long done.
2. **`analyze-core-dump/SKILL.md.tmpl`**
   - Correct the x86_64 gdb path table row (currently line 159) from
     `/opt/output-x86/host/bin/...` to
     `{{BUILDROOT_OUT_X86_FULL}}/host/bin/x86_64-buildroot-linux-gnu-gdb`.
   - Replace the `~/Documentos/Recursos\ Embrace2/analisa-coredump.sh`
     invocation with `{{SKILLS_REPO}}/resources/analisa-coredump.sh`.
   - Replace `~/Documentos/Recursos Embrace2/guia-coredump.md` reference with
     `{{SKILLS_REPO}}/resources/guia-coredump.md`.
3. **`embrace-firmware/SKILL.md.tmpl`, `embrace-monitor/SKILL.md.tmpl`**
   - Replace literal `192.168.10.66` (and any `192.168.10.42`) with phrasing
     like: "the device IP supplied by the user (e.g., via `./deploy.sh
     <DEVICE_IP>`). If no IP was provided, halt and ask the user before
     attempting device access."

All other tokens are mechanical:

| Variable | Replaces |
|---|---|
| `{{BUILDROOT_DIR}}` | `/opt/my-buildroot` |
| `{{BUILDROOT_OUT_X86_FULL}}` | `/opt/output-x86-full` |
| `{{BUILDROOT_OUT_X86_PRO}}` | `/opt/output-x86-pro` |
| `{{BUILDROOT_OUT_ARM}}` | `/opt/output-arm` |
| `{{MONITOR_DIR}}` | `~/Projects/monitor` |
| `{{FIRMWARE_DIR}}` | `~/Projects/aplicacao_ac` |
| `{{DEPLOY_AC3_DIR}}` | `~/Projects/deploy-ac3` |
| `{{DOCS_DIR}}` | `~/IdeaProjects/AC3_Docs` |
| `{{EMBRACE2_DIR}}` | `~/Embrace2` |
| `{{EMBRACE2_DEBUG_DIR}}` | `~/Embrace2_debug` |
| `{{RECURSOS_DIR}}` | `~/Documentos/Recursos Embrace2` |

## README changes

The README needs three edits:

1. **§ Prerequisites** — change the table from "paths the skills assume" to
   "paths configured in `paths.defaults.conf`; override locally via
   `~/.config/embrace-skills/paths.conf` or `<repo>/paths.local.conf`". Drop
   the "normalize to team layout or fork with sed-replaced paths" advice.
2. **§ Install** — replace the manual symlink loops with the new flow:
   ```bash
   git clone git@github.com:emersonscenario/embrace_claude_skills.git ~/Projects/embrace-skills
   cd ~/Projects/embrace-skills
   cp paths.conf.example ~/.config/embrace-skills/paths.conf   # optional, only if your layout differs
   $EDITOR ~/.config/embrace-skills/paths.conf                  # optional
   ./install.sh                                                 # default: global mode
   # or: ./install.sh --mode=per-repo
   ```
3. **§ Updates** — change from "`git pull` is instant" to:
   ```bash
   cd ~/Projects/embrace-skills
   git pull
   ./install.sh --render-only
   ```

## Update flow recap

| Trigger | User action |
|---|---|
| Pulled new templates from upstream | `git pull && ./install.sh --render-only` |
| Edited `~/.config/embrace-skills/paths.conf` | `./install.sh --reconfigure` |
| Added a new skill / changed install mode | `./install.sh [--mode=...]` (full run) |
| Wanted to back out completely | `./uninstall.sh` |

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| User edits `.rendered/<skill>/SKILL.md` directly thinking it's the source | `.rendered/` is gitignored and `install.sh` overwrites it on every render. A `// AUTO-GENERATED FROM <skill>/SKILL.md.tmpl — DO NOT EDIT` header at the top of each rendered file makes this obvious. |
| `RECURSOS_DIR` contains a space, breaking unquoted shell snippets | Renderer outputs literal paths; template author is responsible for quoting in shell snippets (`"{{RECURSOS_DIR}}"/file` → `"~/Documentos/Recursos Embrace2"/file`). Adopt the rule: every `{{*_DIR}}` reference inside a triple-backtick block must be quoted. |
| `paths.conf` exists but is missing keys (e.g., user only edited 2 of 11) | Layering: defaults are sourced first, so missing keys inherit defaults. No "must be complete" requirement. |
| Per-repo install: `<repo>/.claude/skills/` ends up symlinked to the rendered tree, which then references the same repo — circular? | Not circular; symlinks point to `.rendered/` which contains plain `.md` files. Tested mentally; no cycle. |
| Old users with existing symlinks from the v1 install | `install.sh` should `rm -f` any existing symlink at the target before relinking. `uninstall.sh` should clean up both old and new symlink shapes (`-lname '*embrace-skills*'` already does). |

## Out of scope (for this spec)

- Renaming the skills themselves.
- Changing the skill descriptions (`description:` frontmatter) — they keep
  whatever current literal paths they contain. The frontmatter is body, treated
  by the renderer like everything else.
- Reorganizing the `resources/` dir beyond moving the two coredump assets in.
  Future bundled resources can be added later.

## Next step

Hand off to `superpowers:writing-plans` to produce an implementation plan
sequencing the work: install.sh/render.sh authoring, template conversion of
each SKILL.md, resources/ population, README rewrite, end-to-end test on the
maintainer's own machine, then commit.
