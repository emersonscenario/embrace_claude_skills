# Configurable Paths Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the 7 hardcoded skill bodies into templates rendered at install time from `paths.defaults.conf` + a per-user `paths.conf`, bundle the two coredump support files into the repo, drop the legacy x86 output dir and the default device IP, and rewrite the README install/update flow.

**Architecture:** `install.sh` sources `paths.defaults.conf` then optional `~/.config/embrace-skills/paths.conf` (or repo-local `paths.local.conf`), uses `lib/render.sh` to substitute `{{VAR_NAME}}` tokens in each `<skill>/SKILL.md.tmpl` → `.rendered/<skill>/SKILL.md`, then symlinks `.rendered/<name>` into `~/.claude/skills/<name>` (global) or per-repo `.claude/skills/`. Rendered bodies contain literal paths — zero session-token overhead vs today. Bundled support files live in `resources/`.

**Tech Stack:** POSIX shell + bash 4+ (for `${var//pat/repl}`). No external deps. Tests are plain bash scripts with assertion helpers in `tests/lib.sh`.

**Reference spec:** `docs/superpowers/specs/2026-05-11-configurable-paths-design.md`.

---

## File map

### New files (created in this plan)

| Path | Responsibility |
|---|---|
| `paths.defaults.conf` | 11 team-default path variables; shell-source compatible |
| `paths.conf.example` | Annotated user-override template |
| `install.sh` | CLI entry point: `--mode=global\|per-repo`, `--render-only`, `--reconfigure` |
| `uninstall.sh` | Removes symlinks created by `install.sh` |
| `lib/render.sh` | Pure-bash `{{VAR}}` substitution; sourced by `install.sh` |
| `resources/analisa-coredump.sh` | Bundled coredump analyzer (was in `~/Documentos/Recursos Embrace2/`) |
| `resources/guia-coredump.md` | Bundled coredump usage guide |
| `.gitignore` | Excludes `/.rendered/`, `paths.conf`, `paths.local.conf` |
| `tests/lib.sh` | Assertion helpers (`assert_eq`, `assert_file_exists`, `assert_symlink_to`, `fail`) |
| `tests/run-all.sh` | Runs every `tests/test_*.sh` and reports pass/fail |
| `tests/test_render.sh` | Unit tests for `lib/render.sh` |
| `tests/test_install_render_only.sh` | `install.sh --render-only` produces `.rendered/<skill>/SKILL.md` for every skill |
| `tests/test_install_global.sh` | `install.sh --mode=global` symlinks `~/.claude/skills/<name>` → `.rendered/<name>` |
| `tests/test_install_per_repo.sh` | `install.sh --mode=per-repo` symlinks into each target repo's `.claude/skills/` |
| `tests/test_uninstall.sh` | `uninstall.sh` removes those symlinks |
| `tests/test_no_hardcoded_paths.sh` | Greps rendered `SKILL.md` files for any of the 11 retired path patterns; fails if any remain |

### Templated files (renamed `SKILL.md` → `SKILL.md.tmpl` and edited)

| Path | Notable content edits beyond `path → {{VAR}}` |
|---|---|
| `firmware-module-communication/SKILL.md.tmpl` | 1 path; description-only change |
| `add-firmware-module/SKILL.md.tmpl` | 5 paths |
| `embrace-docs/SKILL.md.tmpl` | 6 paths |
| `embrace-monitor/SKILL.md.tmpl` | 8 paths + replace `192.168.10.66` with halt-and-ask wording |
| `embrace-firmware/SKILL.md.tmpl` | 11 paths + replace `192.168.10.66` and `192.168.10.42` |
| `embrace-buildroot/SKILL.md.tmpl` | 36 paths + **delete line 115** (one-time migration note) |
| `analyze-core-dump/SKILL.md.tmpl` | 18 paths + **fix line 159** (legacy `/opt/output-x86/host/bin/...` gdb path → `{{BUILDROOT_OUT_X86_FULL}}/host/bin/...`) + replace coredump script/guide refs with `{{SKILLS_REPO}}/resources/...` |

### Modified files

- `README.md` — rewrite §Prerequisites, §Install, §Updates, §Uninstall.

---

## Conventions

- All template paths use `{{VAR_NAME}}` (exactly two braces, no spaces). Renderer matches `\{\{[A-Z_]+\}\}` literally.
- `paths.defaults.conf` uses `$HOME` not `~` (the latter doesn't expand inside double-quoted strings when `source`d).
- After render, every `{{*_DIR}}` reference inside a triple-backtick block in templates **must be quoted** (`"{{RECURSOS_DIR}}"/file`), because `RECURSOS_DIR` contains a space. The template author is responsible for this; the renderer is dumb.
- Each rendered file starts with the line `<!-- AUTO-GENERATED FROM <skill>/SKILL.md.tmpl — DO NOT EDIT -->` to prevent confused manual edits.
- Tests use `mktemp -d` sandboxes so they never touch the real `~/.claude/skills/`. They override `HOME` and the install-target dirs via env vars.
- `install.sh` honors `EMBRACE_SKILLS_HOME` (defaults to `$HOME`) and `EMBRACE_SKILLS_CLAUDE_DIR` (defaults to `$EMBRACE_SKILLS_HOME/.claude/skills`) so tests can redirect.

---

## Task 1: Test harness bootstrap

**Files:**
- Create: `tests/lib.sh`
- Create: `tests/run-all.sh`

- [ ] **Step 1: Write `tests/lib.sh`**

```bash
# tests/lib.sh — assertion helpers for shell tests.
# Usage in a test: `source "$(dirname "$0")/lib.sh"` at the top.

set -u

_pass=0
_fail=0

fail() {
    echo "  FAIL: $*" >&2
    _fail=$((_fail+1))
    return 1
}

pass() {
    _pass=$((_pass+1))
}

assert_eq() {
    # assert_eq <expected> <actual> [message]
    local expected="$1" actual="$2" msg="${3:-}"
    if [ "$expected" = "$actual" ]; then
        pass
    else
        fail "${msg:-equality}: expected [$expected], got [$actual]"
    fi
}

assert_file_exists() {
    [ -f "$1" ] && pass || fail "expected file: $1"
}

assert_file_not_exists() {
    [ ! -e "$1" ] && pass || fail "expected file to NOT exist: $1"
}

assert_symlink_to() {
    # assert_symlink_to <link> <expected_target>
    local link="$1" expected="$2"
    if [ -L "$link" ]; then
        local actual
        actual=$(readlink "$link")
        if [ "$actual" = "$expected" ]; then
            pass
        else
            fail "symlink $link → $actual, expected → $expected"
        fi
    else
        fail "expected symlink: $link"
    fi
}

assert_contains() {
    # assert_contains <haystack_file> <needle>
    if grep -qF -- "$2" "$1"; then
        pass
    else
        fail "expected $1 to contain: $2"
    fi
}

assert_not_contains() {
    # assert_not_contains <haystack_file> <needle>
    if grep -qF -- "$2" "$1"; then
        fail "expected $1 to NOT contain: $2"
    else
        pass
    fi
}

summary() {
    echo "  ${_pass} passed, ${_fail} failed"
    [ "$_fail" -eq 0 ]
}

# Sandbox helpers
mk_sandbox() {
    # Returns a fresh tmp dir; caller is responsible for cleanup.
    mktemp -d -t embrace-skills-test.XXXXXX
}
```

- [ ] **Step 2: Write `tests/run-all.sh`**

```bash
#!/usr/bin/env bash
# tests/run-all.sh — runs every tests/test_*.sh in the same dir.
set -u
cd "$(dirname "$0")"
overall_fail=0
for t in test_*.sh; do
    [ -f "$t" ] || continue
    echo "==> $t"
    if bash "$t"; then
        echo "  OK"
    else
        echo "  FAIL"
        overall_fail=1
    fi
done
exit "$overall_fail"
```

- [ ] **Step 3: Make `tests/run-all.sh` executable and run it**

```bash
chmod +x tests/run-all.sh
./tests/run-all.sh
```

Expected: exits 0 (no test files yet, loop body skipped, `overall_fail` remains 0).

- [ ] **Step 4: Commit**

```bash
git add tests/lib.sh tests/run-all.sh
git commit -m "test: bootstrap shell test harness"
```

---

## Task 2: Path config files

**Files:**
- Create: `paths.defaults.conf`
- Create: `paths.conf.example`

- [ ] **Step 1: Write `paths.defaults.conf`**

```sh
# paths.defaults.conf — team-default host-machine paths for the skill set.
# Sourced by install.sh. User overrides go in:
#   ~/.config/embrace-skills/paths.conf  (per-user, recommended)
#   ./paths.local.conf                   (per-repo, gitignored)
# Override files only need to contain the variables that differ from defaults.

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

- [ ] **Step 2: Write `paths.conf.example`**

```sh
# paths.conf.example — copy to ~/.config/embrace-skills/paths.conf (or
# <repo>/paths.local.conf) and uncomment only the lines you need to change.
# Variables not set here inherit from paths.defaults.conf.

# Buildroot external tree
# BUILDROOT_DIR="/opt/my-buildroot"

# Buildroot output trees (3 variants)
# BUILDROOT_OUT_X86_FULL="/opt/output-x86-full"
# BUILDROOT_OUT_X86_PRO="/opt/output-x86-pro"
# BUILDROOT_OUT_ARM="/opt/output-arm"

# Source repos
# MONITOR_DIR="$HOME/Projects/monitor"
# FIRMWARE_DIR="$HOME/Projects/aplicacao_ac"
# DEPLOY_AC3_DIR="$HOME/Projects/deploy-ac3"
# DOCS_DIR="$HOME/IdeaProjects/AC3_Docs"

# Release / debug artefact dirs
# EMBRACE2_DIR="$HOME/Embrace2"
# EMBRACE2_DEBUG_DIR="$HOME/Embrace2_debug"

# Misc working dir (used by buildroot provisioning scripts for the Banana Pi base image)
# RECURSOS_DIR="$HOME/Documentos/Recursos Embrace2"
```

- [ ] **Step 3: Verify both files exist and are syntactically valid shell**

```bash
bash -n paths.defaults.conf && bash -n paths.conf.example && echo OK
```

Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add paths.defaults.conf paths.conf.example
git commit -m "config: introduce paths.defaults.conf and example"
```

---

## Task 3: Render library — failing test

**Files:**
- Create: `tests/test_render.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/test_render.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
source "$HERE/lib.sh"

# Source under test (does not exist yet).
source "$REPO/lib/render.sh"

# --- test 1: substitute a single variable ---
SANDBOX=$(mk_sandbox)
trap 'rm -rf "$SANDBOX"' EXIT

cat >"$SANDBOX/in.tmpl" <<'EOF'
firmware lives at {{FIRMWARE_DIR}}/Core/
EOF

FIRMWARE_DIR="/work/firmware" \
    render_file "$SANDBOX/in.tmpl" "$SANDBOX/out.md"

assert_file_exists "$SANDBOX/out.md"
assert_contains "$SANDBOX/out.md" "firmware lives at /work/firmware/Core/"
assert_not_contains "$SANDBOX/out.md" "{{FIRMWARE_DIR}}"

# --- test 2: multiple distinct variables ---
cat >"$SANDBOX/in2.tmpl" <<'EOF'
buildroot={{BUILDROOT_DIR}} monitor={{MONITOR_DIR}} repo={{SKILLS_REPO}}
EOF

BUILDROOT_DIR="/b" MONITOR_DIR="/m" SKILLS_REPO="/r" \
    render_file "$SANDBOX/in2.tmpl" "$SANDBOX/out2.md"

assert_contains "$SANDBOX/out2.md" "buildroot=/b monitor=/m repo=/r"

# --- test 3: unresolved token fails loud ---
cat >"$SANDBOX/in3.tmpl" <<'EOF'
{{NOT_SET}}
EOF

if render_file "$SANDBOX/in3.tmpl" "$SANDBOX/out3.md" 2>/dev/null; then
    fail "render_file should have failed on unresolved token"
else
    pass
fi

# --- test 4: variable value with spaces ---
cat >"$SANDBOX/in4.tmpl" <<'EOF'
recursos={{RECURSOS_DIR}}
EOF

RECURSOS_DIR="/path with space" \
    render_file "$SANDBOX/in4.tmpl" "$SANDBOX/out4.md"

assert_contains "$SANDBOX/out4.md" "recursos=/path with space"

summary
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash tests/test_render.sh
```

Expected: fails with "No such file or directory" on `source "$REPO/lib/render.sh"`.

- [ ] **Step 3: Implement `lib/render.sh`**

```bash
#!/usr/bin/env bash
# lib/render.sh — substitute {{VAR_NAME}} tokens with the value of $VAR_NAME
# in the current shell environment. Caller is responsible for `source`ing the
# config files first.

# render_file <input_tmpl> <output_path>
# Returns non-zero if any {{...}} token remains unresolved after substitution.
render_file() {
    local in="$1" out="$2"
    local content
    content=$(cat "$in")

    # Find all distinct {{VAR}} tokens and substitute each with $VAR.
    local tokens
    tokens=$(printf '%s' "$content" | grep -oE '\{\{[A-Z_]+\}\}' | sort -u || true)

    local token name value
    for token in $tokens; do
        name=${token#\{\{}
        name=${name%\}\}}
        # `declare -p` works cleanly under `set -u` — it just returns non-zero
        # if the variable is unset, rather than aborting the shell.
        if ! declare -p "$name" >/dev/null 2>&1; then
            echo "render_file: unresolved token {{$name}} in $in" >&2
            return 1
        fi
        value=${!name}
        # Plain string replacement; bash global substitution.
        content=${content//"$token"/"$value"}
    done

    mkdir -p "$(dirname "$out")"
    printf '%s\n' "$content" >"$out"
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash tests/test_render.sh
```

Expected: `4 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add lib/render.sh tests/test_render.sh
git commit -m "feat: lib/render.sh — {{VAR}} substitution"
```

---

## Task 4: install.sh `--render-only` — failing test

**Files:**
- Create: `tests/test_install_render_only.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/test_install_render_only.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
source "$HERE/lib.sh"

SANDBOX=$(mk_sandbox)
trap 'rm -rf "$SANDBOX"' EXIT

# Build a tiny fake repo with one template skill.
FAKEREPO="$SANDBOX/repo"
mkdir -p "$FAKEREPO/dummy-skill" "$FAKEREPO/lib"

cp "$REPO/lib/render.sh" "$FAKEREPO/lib/render.sh"
cp "$REPO/install.sh" "$FAKEREPO/install.sh"   # under test — does not exist yet
chmod +x "$FAKEREPO/install.sh"

cat >"$FAKEREPO/paths.defaults.conf" <<'EOF'
FIRMWARE_DIR="/default/firmware"
MONITOR_DIR="/default/monitor"
EOF

cat >"$FAKEREPO/dummy-skill/SKILL.md.tmpl" <<'EOF'
---
name: dummy-skill
description: dummy
---
fw={{FIRMWARE_DIR}} mon={{MONITOR_DIR}} repo={{SKILLS_REPO}}
EOF

# Run render-only with no user override.
( cd "$FAKEREPO" && ./install.sh --render-only )

RENDERED="$FAKEREPO/.rendered/dummy-skill/SKILL.md"
assert_file_exists "$RENDERED"
assert_contains "$RENDERED" "fw=/default/firmware"
assert_contains "$RENDERED" "mon=/default/monitor"
assert_contains "$RENDERED" "repo=$FAKEREPO"
assert_contains "$RENDERED" "AUTO-GENERATED"
assert_not_contains "$RENDERED" "{{"

# Run again with a user override.
cat >"$FAKEREPO/paths.local.conf" <<'EOF'
FIRMWARE_DIR="/over/firmware"
EOF

( cd "$FAKEREPO" && ./install.sh --render-only )
assert_contains "$RENDERED" "fw=/over/firmware"
assert_contains "$RENDERED" "mon=/default/monitor"  # not overridden, falls back

summary
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash tests/test_install_render_only.sh
```

Expected: fails with "No such file or directory" on `cp "$REPO/install.sh"`.

- [ ] **Step 3: Implement `install.sh`**

```bash
#!/usr/bin/env bash
# install.sh — render skill templates and (optionally) symlink them into
# ~/.claude/skills/ or per-repo .claude/skills/ trees.
set -eu

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

MODE="global"
RENDER_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --mode=*) MODE="${1#--mode=}" ;;
        --render-only|--reconfigure) RENDER_ONLY=1 ;;
        -h|--help)
            cat <<EOF
Usage: ./install.sh [--mode=global|per-repo] [--render-only|--reconfigure]

  --mode=global       Symlink rendered skills into ~/.claude/skills/ (default).
  --mode=per-repo     Symlink rendered skills into each target repo's
                      .claude/skills/ (BUILDROOT_DIR, MONITOR_DIR, FIRMWARE_DIR,
                      DOCS_DIR), per the README per-repo mapping.
  --render-only       Render templates only; do not (re)create symlinks.
  --reconfigure       Alias for --render-only (clearer intent after editing
                      paths.conf).
EOF
            exit 0
            ;;
        *) echo "install.sh: unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

# Load config: defaults first, then overrides.
# shellcheck disable=SC1091
source "$REPO/paths.defaults.conf"

USER_CONF="${EMBRACE_SKILLS_HOME:-$HOME}/.config/embrace-skills/paths.conf"
[ -f "$USER_CONF" ] && source "$USER_CONF"
[ -f "$REPO/paths.local.conf" ] && source "$REPO/paths.local.conf"

SKILLS_REPO="$REPO"
export SKILLS_REPO

# Validate (warn-only): every variable should point to an existing dir.
for var in BUILDROOT_DIR BUILDROOT_OUT_X86_FULL BUILDROOT_OUT_X86_PRO \
           BUILDROOT_OUT_ARM MONITOR_DIR FIRMWARE_DIR DEPLOY_AC3_DIR \
           DOCS_DIR EMBRACE2_DIR EMBRACE2_DEBUG_DIR RECURSOS_DIR; do
    if [ -z "${!var+set}" ]; then
        echo "install.sh: $var not set (missing from defaults?)" >&2
        continue
    fi
    if [ ! -d "${!var}" ]; then
        echo "install.sh: WARNING: $var=${!var} does not exist on this machine" >&2
    fi
done

# Render every <skill>/SKILL.md.tmpl into .rendered/<skill>/SKILL.md.
# shellcheck disable=SC1091
source "$REPO/lib/render.sh"

mkdir -p "$REPO/.rendered"
SKILLS=()
for tmpl in "$REPO"/*/SKILL.md.tmpl; do
    [ -f "$tmpl" ] || continue
    skill=$(basename "$(dirname "$tmpl")")
    out="$REPO/.rendered/$skill/SKILL.md"
    mkdir -p "$REPO/.rendered/$skill"
    {
        echo "<!-- AUTO-GENERATED FROM $skill/SKILL.md.tmpl — DO NOT EDIT -->"
        echo
    } >"$out.header"
    render_file "$tmpl" "$out.body"
    cat "$out.header" "$out.body" >"$out"
    rm -f "$out.header" "$out.body"
    SKILLS+=("$skill")
done

if [ "$RENDER_ONLY" -eq 1 ]; then
    echo "Rendered ${#SKILLS[@]} skill(s) into $REPO/.rendered/"
    exit 0
fi

# Symlink phase (Tasks 5 & 6 fill these in).
echo "install.sh: --mode=$MODE not yet implemented in this task" >&2
exit 0
```

Don't forget:

```bash
chmod +x install.sh
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash tests/test_install_render_only.sh
```

Expected: `7 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_install_render_only.sh
git commit -m "feat: install.sh --render-only with defaults+override layering"
```

---

## Task 5: install.sh `--mode=global` — failing test

**Files:**
- Create: `tests/test_install_global.sh`
- Modify: `install.sh` (symlink phase)

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/test_install_global.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
source "$HERE/lib.sh"

SANDBOX=$(mk_sandbox)
trap 'rm -rf "$SANDBOX"' EXIT

# Stand up a fake repo with two skills.
FAKEREPO="$SANDBOX/repo"
mkdir -p "$FAKEREPO/lib" "$FAKEREPO/skill-a" "$FAKEREPO/skill-b"
cp "$REPO/lib/render.sh" "$FAKEREPO/lib/"
cp "$REPO/install.sh"    "$FAKEREPO/"
chmod +x "$FAKEREPO/install.sh"

cat >"$FAKEREPO/paths.defaults.conf" <<'EOF'
BUILDROOT_DIR="/b"
BUILDROOT_OUT_X86_FULL="/b/full"
BUILDROOT_OUT_X86_PRO="/b/pro"
BUILDROOT_OUT_ARM="/b/arm"
MONITOR_DIR="/m"
FIRMWARE_DIR="/f"
DEPLOY_AC3_DIR="/d"
DOCS_DIR="/docs"
EMBRACE2_DIR="/e"
EMBRACE2_DEBUG_DIR="/edbg"
RECURSOS_DIR="/rec"
EOF
echo "ok-a" >"$FAKEREPO/skill-a/SKILL.md.tmpl"
echo "ok-b" >"$FAKEREPO/skill-b/SKILL.md.tmpl"

# Sandboxed HOME — must not touch real ~/.claude/skills.
FAKEHOME="$SANDBOX/home"
mkdir -p "$FAKEHOME/.claude/skills"

EMBRACE_SKILLS_HOME="$FAKEHOME" \
    bash "$FAKEREPO/install.sh" --mode=global

assert_symlink_to "$FAKEHOME/.claude/skills/skill-a" "$FAKEREPO/.rendered/skill-a"
assert_symlink_to "$FAKEHOME/.claude/skills/skill-b" "$FAKEREPO/.rendered/skill-b"
assert_file_exists "$FAKEHOME/.claude/skills/skill-a/SKILL.md"

# Re-running should be idempotent (no error, symlinks still correct).
EMBRACE_SKILLS_HOME="$FAKEHOME" \
    bash "$FAKEREPO/install.sh" --mode=global
assert_symlink_to "$FAKEHOME/.claude/skills/skill-a" "$FAKEREPO/.rendered/skill-a"

summary
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash tests/test_install_global.sh
```

Expected: 3 failures (the asserts about the symlinks — install.sh currently bails with "not yet implemented").

- [ ] **Step 3: Implement the global symlink phase in `install.sh`**

Replace the last two lines (`echo "install.sh: --mode=$MODE not yet implemented..."; exit 0`) with:

```bash
case "$MODE" in
    global)
        TARGET_DIR="${EMBRACE_SKILLS_HOME:-$HOME}/.claude/skills"
        mkdir -p "$TARGET_DIR"
        for skill in "${SKILLS[@]}"; do
            ln -sfn "$REPO/.rendered/$skill" "$TARGET_DIR/$skill"
        done
        echo "Linked ${#SKILLS[@]} skill(s) into $TARGET_DIR"
        ;;
    per-repo)
        # Task 6 fills this in.
        echo "install.sh: --mode=per-repo not yet implemented" >&2
        exit 1
        ;;
    *)
        echo "install.sh: unknown mode: $MODE" >&2
        exit 2
        ;;
esac
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash tests/test_install_global.sh
```

Expected: `3 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_install_global.sh
git commit -m "feat: install.sh --mode=global symlink phase"
```

---

## Task 6: install.sh `--mode=per-repo` — failing test

**Files:**
- Create: `tests/test_install_per_repo.sh`
- Modify: `install.sh` (per-repo branch)

Per-repo mapping (from the design spec, matching today's README option-2):

| Target | Skills |
|---|---|
| `$BUILDROOT_DIR/.claude/skills/` | `embrace-buildroot`, `analyze-core-dump`, `embrace-docs` |
| `$MONITOR_DIR/.claude/skills/` | `embrace-monitor`, `analyze-core-dump`, `embrace-docs` |
| `$FIRMWARE_DIR/.claude/skills/` | `embrace-firmware`, `add-firmware-module`, `firmware-module-communication`, `analyze-core-dump`, `embrace-docs` |
| `$DOCS_DIR/.claude/skills/` | `embrace-docs` |

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/test_install_per_repo.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
source "$HERE/lib.sh"

SANDBOX=$(mk_sandbox)
trap 'rm -rf "$SANDBOX"' EXIT

FAKEREPO="$SANDBOX/repo"
mkdir -p "$FAKEREPO/lib"
cp "$REPO/lib/render.sh" "$FAKEREPO/lib/"
cp "$REPO/install.sh"    "$FAKEREPO/"
chmod +x "$FAKEREPO/install.sh"

# Stand up minimal skill stubs — only the ones the per-repo mapping references.
for s in embrace-buildroot embrace-monitor embrace-firmware add-firmware-module \
         firmware-module-communication analyze-core-dump embrace-docs; do
    mkdir -p "$FAKEREPO/$s"
    echo "$s" >"$FAKEREPO/$s/SKILL.md.tmpl"
done

# Stand up sandboxed target repos that will receive the symlinks.
BR="$SANDBOX/br"; MON="$SANDBOX/mon"; FW="$SANDBOX/fw"; DCS="$SANDBOX/docs"
mkdir -p "$BR" "$MON" "$FW" "$DCS"

cat >"$FAKEREPO/paths.defaults.conf" <<EOF
BUILDROOT_DIR="$BR"
BUILDROOT_OUT_X86_FULL="$BR/full"
BUILDROOT_OUT_X86_PRO="$BR/pro"
BUILDROOT_OUT_ARM="$BR/arm"
MONITOR_DIR="$MON"
FIRMWARE_DIR="$FW"
DEPLOY_AC3_DIR="$SANDBOX/dep"
DOCS_DIR="$DCS"
EMBRACE2_DIR="$SANDBOX/e2"
EMBRACE2_DEBUG_DIR="$SANDBOX/e2dbg"
RECURSOS_DIR="$SANDBOX/rec"
EOF

# Sandboxed HOME so a real ~/.config/embrace-skills/paths.conf can't pollute.
FAKEHOME="$SANDBOX/home"
mkdir -p "$FAKEHOME"

EMBRACE_SKILLS_HOME="$FAKEHOME" bash "$FAKEREPO/install.sh" --mode=per-repo

# Buildroot tree gets buildroot + core-dump + docs.
assert_symlink_to "$BR/.claude/skills/embrace-buildroot"  "$FAKEREPO/.rendered/embrace-buildroot"
assert_symlink_to "$BR/.claude/skills/analyze-core-dump"  "$FAKEREPO/.rendered/analyze-core-dump"
assert_symlink_to "$BR/.claude/skills/embrace-docs"       "$FAKEREPO/.rendered/embrace-docs"

# Monitor tree gets monitor + core-dump + docs.
assert_symlink_to "$MON/.claude/skills/embrace-monitor"   "$FAKEREPO/.rendered/embrace-monitor"
assert_symlink_to "$MON/.claude/skills/analyze-core-dump" "$FAKEREPO/.rendered/analyze-core-dump"

# Firmware tree gets firmware + add-module + module-comm + core-dump + docs.
assert_symlink_to "$FW/.claude/skills/embrace-firmware"             "$FAKEREPO/.rendered/embrace-firmware"
assert_symlink_to "$FW/.claude/skills/add-firmware-module"          "$FAKEREPO/.rendered/add-firmware-module"
assert_symlink_to "$FW/.claude/skills/firmware-module-communication" "$FAKEREPO/.rendered/firmware-module-communication"

# Docs tree only gets docs.
assert_symlink_to "$DCS/.claude/skills/embrace-docs"      "$FAKEREPO/.rendered/embrace-docs"
assert_file_not_exists "$DCS/.claude/skills/embrace-firmware"

summary
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash tests/test_install_per_repo.sh
```

Expected: install.sh exits 1 with "not yet implemented"; assertions fail.

- [ ] **Step 3: Implement the per-repo branch in `install.sh`**

Replace the `per-repo)` branch added in Task 5 with:

```bash
    per-repo)
        # mapping: <target_var>=<space-separated skill list>
        declare -A PER_REPO_MAP=(
            [BUILDROOT_DIR]="embrace-buildroot analyze-core-dump embrace-docs"
            [MONITOR_DIR]="embrace-monitor analyze-core-dump embrace-docs"
            [FIRMWARE_DIR]="embrace-firmware add-firmware-module firmware-module-communication analyze-core-dump embrace-docs"
            [DOCS_DIR]="embrace-docs"
        )
        for target_var in "${!PER_REPO_MAP[@]}"; do
            target_root="${!target_var}"
            if [ ! -d "$target_root" ]; then
                echo "install.sh: skipping $target_var=$target_root (not a directory)" >&2
                continue
            fi
            mkdir -p "$target_root/.claude/skills"
            for skill in ${PER_REPO_MAP[$target_var]}; do
                if [ ! -d "$REPO/.rendered/$skill" ]; then
                    echo "install.sh: skipping $skill (not rendered)" >&2
                    continue
                fi
                ln -sfn "$REPO/.rendered/$skill" "$target_root/.claude/skills/$skill"
            done
        done
        echo "Per-repo symlinks installed under: BUILDROOT_DIR, MONITOR_DIR, FIRMWARE_DIR, DOCS_DIR"
        ;;
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash tests/test_install_per_repo.sh
```

Expected: all asserts pass.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_install_per_repo.sh
git commit -m "feat: install.sh --mode=per-repo symlink phase"
```

---

## Task 7: uninstall.sh — failing test

**Files:**
- Create: `tests/test_uninstall.sh`
- Create: `uninstall.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# tests/test_uninstall.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
source "$HERE/lib.sh"

SANDBOX=$(mk_sandbox)
trap 'rm -rf "$SANDBOX"' EXIT

FAKEREPO="$SANDBOX/repo"
mkdir -p "$FAKEREPO/lib"
cp "$REPO/lib/render.sh" "$FAKEREPO/lib/"
cp "$REPO/install.sh"    "$FAKEREPO/"
cp "$REPO/uninstall.sh"  "$FAKEREPO/"   # under test — does not exist yet
chmod +x "$FAKEREPO/install.sh" "$FAKEREPO/uninstall.sh"

# One minimal skill stub.
mkdir -p "$FAKEREPO/foo"
echo "x" >"$FAKEREPO/foo/SKILL.md.tmpl"

cat >"$FAKEREPO/paths.defaults.conf" <<'EOF'
BUILDROOT_DIR="/b"
BUILDROOT_OUT_X86_FULL="/b/full"
BUILDROOT_OUT_X86_PRO="/b/pro"
BUILDROOT_OUT_ARM="/b/arm"
MONITOR_DIR="/m"
FIRMWARE_DIR="/f"
DEPLOY_AC3_DIR="/d"
DOCS_DIR="/docs"
EMBRACE2_DIR="/e"
EMBRACE2_DEBUG_DIR="/edbg"
RECURSOS_DIR="/rec"
EOF

FAKEHOME="$SANDBOX/home"
mkdir -p "$FAKEHOME/.claude/skills"

# Plant an unrelated symlink — uninstall must NOT touch it.
ln -s /some/other/place "$FAKEHOME/.claude/skills/unrelated"

EMBRACE_SKILLS_HOME="$FAKEHOME" bash "$FAKEREPO/install.sh" --mode=global
assert_symlink_to "$FAKEHOME/.claude/skills/foo" "$FAKEREPO/.rendered/foo"

EMBRACE_SKILLS_HOME="$FAKEHOME" bash "$FAKEREPO/uninstall.sh" --mode=global
assert_file_not_exists "$FAKEHOME/.claude/skills/foo"
# Unrelated symlink must survive.
[ -L "$FAKEHOME/.claude/skills/unrelated" ] && pass || fail "unrelated symlink got removed"

summary
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: fails on `cp "$REPO/uninstall.sh"`.

- [ ] **Step 3: Implement `uninstall.sh`**

```bash
#!/usr/bin/env bash
# uninstall.sh — remove symlinks created by install.sh. Does not touch
# .rendered/, paths.conf, or any unrelated symlink.
set -eu

REPO="$(cd "$(dirname "$0")" && pwd)"
MODE="global"

while [ $# -gt 0 ]; do
    case "$1" in
        --mode=*) MODE="${1#--mode=}" ;;
        -h|--help) echo "Usage: ./uninstall.sh [--mode=global|per-repo]"; exit 0 ;;
        *) echo "uninstall.sh: unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

# Need the conf to know per-repo targets.
# shellcheck disable=SC1091
source "$REPO/paths.defaults.conf"
USER_CONF="${EMBRACE_SKILLS_HOME:-$HOME}/.config/embrace-skills/paths.conf"
[ -f "$USER_CONF" ] && source "$USER_CONF"
[ -f "$REPO/paths.local.conf" ] && source "$REPO/paths.local.conf"

remove_links_in() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    local removed=0
    for entry in "$dir"/*; do
        [ -L "$entry" ] || continue
        local target
        target=$(readlink "$entry")
        case "$target" in
            "$REPO/.rendered/"*) rm -f "$entry"; removed=$((removed+1)) ;;
        esac
    done
    echo "  $dir: removed $removed link(s)"
}

case "$MODE" in
    global)
        remove_links_in "${EMBRACE_SKILLS_HOME:-$HOME}/.claude/skills"
        ;;
    per-repo)
        for target_var in BUILDROOT_DIR MONITOR_DIR FIRMWARE_DIR DOCS_DIR; do
            remove_links_in "${!target_var}/.claude/skills"
        done
        ;;
    *) echo "uninstall.sh: unknown mode: $MODE" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
chmod +x uninstall.sh
bash tests/test_uninstall.sh
```

Expected: `3 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add uninstall.sh tests/test_uninstall.sh
git commit -m "feat: uninstall.sh removes only our symlinks"
```

---

## Task 8: `.gitignore`

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Write `.gitignore`**

```
# install.sh output (per-user, regenerated by ./install.sh --render-only)
/.rendered/

# Local config overrides
/paths.conf
/paths.local.conf

# Editor/OS
*.swp
.DS_Store
```

- [ ] **Step 2: Verify `.rendered/` is now ignored**

```bash
mkdir -p .rendered/test && touch .rendered/test/x
git status --short -- .rendered/ paths.conf paths.local.conf
```

Expected: empty output (none of these tracked).

```bash
rm -rf .rendered
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore .rendered/ and user paths.conf"
```

---

## Task 9: Bundle resources/ — analisa-coredump.sh and guia-coredump.md

**Files:**
- Create: `resources/analisa-coredump.sh`
- Create: `resources/guia-coredump.md`

- [ ] **Step 1: Verify source files exist**

```bash
ls -l "$HOME/Documentos/Recursos Embrace2/analisa-coredump.sh" \
      "$HOME/Documentos/Recursos Embrace2/guia-coredump.md"
```

Expected: both files listed. If either is missing, STOP and ask the maintainer to provide them — the plan can't continue without these.

- [ ] **Step 2: Copy into the repo, preserve executable bit on the script**

```bash
mkdir -p resources
cp "$HOME/Documentos/Recursos Embrace2/analisa-coredump.sh" resources/
cp "$HOME/Documentos/Recursos Embrace2/guia-coredump.md"    resources/
chmod +x resources/analisa-coredump.sh
```

- [ ] **Step 3: Sanity-check**

```bash
test -x resources/analisa-coredump.sh && echo OK
head -1 resources/analisa-coredump.sh           # should be a shebang
test -f resources/guia-coredump.md  && echo OK
```

Expected: two `OK` lines and a shebang line.

- [ ] **Step 4: Commit**

```bash
git add resources/
git commit -m "feat: bundle analisa-coredump.sh + guia-coredump.md in resources/"
```

---

## Task 10: Hardcoded-paths integration test (will drive Tasks 11–17)

**Files:**
- Create: `tests/test_no_hardcoded_paths.sh`

This test enumerates the retired hardcoded patterns and fails if any appears in
the rendered output of any skill. It is **expected to fail now** with all 7
skills listed (because none have been converted). Each conversion task in 11–17
brings the failure count down.

- [ ] **Step 1: Write the test**

```bash
#!/usr/bin/env bash
# tests/test_no_hardcoded_paths.sh
# Renders all skills with the defaults and scans for any retired hardcoded path.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
source "$HERE/lib.sh"

# Render fresh (without symlinking).
( cd "$REPO" && ./install.sh --render-only ) >/dev/null

# Retired patterns. Each must not appear in any rendered SKILL.md.
PATTERNS=(
    "/opt/my-buildroot"
    "/opt/output-x86-full"
    "/opt/output-x86-pro"
    "/opt/output-arm"
    "/opt/output-x86"                   # legacy — dropped entirely
    "~/Projects/monitor"
    "~/Projects/aplicacao_ac"
    "~/Projects/deploy-ac3"
    "~/IdeaProjects/AC3_Docs"
    "~/Embrace2/"
    "~/Embrace2_debug"
    "~/Documentos/Recursos"
    "192.168.10.66"
    "192.168.10.42"
)

shopt -s nullglob
RENDERED=("$REPO"/.rendered/*/SKILL.md)
if [ "${#RENDERED[@]}" -eq 0 ]; then
    fail "no rendered SKILL.md files found"
    summary; exit
fi

for f in "${RENDERED[@]}"; do
    skill=$(basename "$(dirname "$f")")
    for p in "${PATTERNS[@]}"; do
        if grep -qF -- "$p" "$f"; then
            fail "$skill still contains [$p]"
            break
        fi
    done
done

summary
```

- [ ] **Step 2: Run the test — expect failures**

```bash
bash tests/test_no_hardcoded_paths.sh
```

Expected: fails with one line per still-unconverted skill (today: 0 rendered files exist — no `*.tmpl` yet — so it fails with "no rendered SKILL.md files found"). That's fine for now; Task 11 starts producing templates.

- [ ] **Step 3: Commit**

```bash
git add tests/test_no_hardcoded_paths.sh
git commit -m "test: scan rendered skills for retired hardcoded paths"
```

---

## Task 11: Convert `firmware-module-communication` (smallest)

**Files:**
- Modify: `firmware-module-communication/SKILL.md` → `firmware-module-communication/SKILL.md.tmpl`

This skill has **1 path occurrence** (only in the `description:` frontmatter).

- [ ] **Step 1: Rename to .tmpl**

```bash
git mv firmware-module-communication/SKILL.md firmware-module-communication/SKILL.md.tmpl
```

- [ ] **Step 2: Edit the file**

In `firmware-module-communication/SKILL.md.tmpl`, replace:
- `~/Projects/aplicacao_ac/` → `{{FIRMWARE_DIR}}/`

Verify the only path-pattern remaining is `{{FIRMWARE_DIR}}`:

```bash
grep -nE '(/opt/(my-buildroot|output-)|~/Projects/(monitor|aplicacao_ac|deploy-ac3)|~/IdeaProjects/AC3_Docs|~/Embrace2(/|_debug/)|~/Documentos/Recursos|192\.168\.)' firmware-module-communication/SKILL.md.tmpl
```

Expected: no output.

- [ ] **Step 3: Render and run the integration test**

```bash
./install.sh --render-only
bash tests/test_no_hardcoded_paths.sh 2>&1 | grep firmware-module-communication
```

Expected: no line matching `firmware-module-communication` in the output (it's clean).

- [ ] **Step 4: Commit**

```bash
git add firmware-module-communication/SKILL.md.tmpl
git commit -m "refactor: firmware-module-communication → template"
```

---

## Task 12: Convert `add-firmware-module`

**Files:**
- Modify: `add-firmware-module/SKILL.md` → `add-firmware-module/SKILL.md.tmpl`

5 path occurrences (per the audit). Affected lines (current `SKILL.md`):

| Line | Original | Replacement |
|---|---|---|
| 3 (description) | `~/Projects/aplicacao_ac/` | `{{FIRMWARE_DIR}}/` |
| 220 | `~/Projects/aplicacao_ac/docs/log_i18n_keys.md` | `{{FIRMWARE_DIR}}/docs/log_i18n_keys.md` |
| 221 | `~/Projects/aplicacao_ac/docs/logs_inteligentes_por_modulo.md` | `{{FIRMWARE_DIR}}/docs/logs_inteligentes_por_modulo.md` |
| 227 | `cd ~/Projects/aplicacao_ac` | `cd {{FIRMWARE_DIR}}` |
| 258 | `~/IdeaProjects/AC3_Docs/docs/Embrace2/Modulos/Foo.md` | `{{DOCS_DIR}}/docs/Embrace2/Modulos/Foo.md` |

- [ ] **Step 1: Rename**

```bash
git mv add-firmware-module/SKILL.md add-firmware-module/SKILL.md.tmpl
```

- [ ] **Step 2: Apply the 5 replacements**

Use 5 `sed -i` calls or hand-edit. After editing, verify:

```bash
grep -nE '(/opt/(my-buildroot|output-)|~/Projects/(monitor|aplicacao_ac|deploy-ac3)|~/IdeaProjects/AC3_Docs|~/Embrace2(/|_debug/)|~/Documentos/Recursos|192\.168\.)' add-firmware-module/SKILL.md.tmpl
```

Expected: no output.

- [ ] **Step 3: Render and run integration test for this skill**

```bash
./install.sh --render-only
bash tests/test_no_hardcoded_paths.sh 2>&1 | grep add-firmware-module
```

Expected: no line matching `add-firmware-module`.

- [ ] **Step 4: Commit**

```bash
git add add-firmware-module/SKILL.md.tmpl
git commit -m "refactor: add-firmware-module → template"
```

---

## Task 13: Convert `embrace-docs`

**Files:**
- Modify: `embrace-docs/SKILL.md` → `embrace-docs/SKILL.md.tmpl`

6 path occurrences. Replacements:

| Original | Replacement |
|---|---|
| `/opt/my-buildroot/` (description and L17) | `{{BUILDROOT_DIR}}/` |
| `~/Projects/monitor/` (description and L17) | `{{MONITOR_DIR}}/` |
| `~/Projects/aplicacao_ac/` (description and L17) | `{{FIRMWARE_DIR}}/` |
| `~/IdeaProjects/AC3_Docs/` (L10) | `{{DOCS_DIR}}/` |
| `git -C /opt/my-buildroot ...` (L29) | `git -C {{BUILDROOT_DIR}} ...` |
| `git -C ~/Projects/monitor ...` (L30) | `git -C {{MONITOR_DIR}} ...` |
| `git -C ~/Projects/aplicacao_ac ...` (L31) | `git -C {{FIRMWARE_DIR}} ...` |

- [ ] **Step 1: Rename**

```bash
git mv embrace-docs/SKILL.md embrace-docs/SKILL.md.tmpl
```

- [ ] **Step 2: Apply replacements; verify clean**

```bash
grep -nE '(/opt/(my-buildroot|output-)|~/Projects/(monitor|aplicacao_ac|deploy-ac3)|~/IdeaProjects/AC3_Docs|~/Embrace2(/|_debug/)|~/Documentos/Recursos|192\.168\.)' embrace-docs/SKILL.md.tmpl
```

Expected: no output.

- [ ] **Step 3: Render and verify**

```bash
./install.sh --render-only
bash tests/test_no_hardcoded_paths.sh 2>&1 | grep embrace-docs
```

Expected: no line matching `embrace-docs`.

- [ ] **Step 4: Commit**

```bash
git add embrace-docs/SKILL.md.tmpl
git commit -m "refactor: embrace-docs → template"
```

---

## Task 14: Convert `embrace-monitor`

**Files:**
- Modify: `embrace-monitor/SKILL.md` → `embrace-monitor/SKILL.md.tmpl`

8 path occurrences + the `192.168.10.66` references.

Replacements:

| Original | Replacement |
|---|---|
| `~/Projects/monitor/` (multiple) | `{{MONITOR_DIR}}/` |
| `/opt/monitor/www/` | **leave** — this is on-device (EmbraceOS contract) |
| `192.168.10.66` | (see step 3 below) |

- [ ] **Step 1: Locate the IP references**

```bash
grep -n '192\.168' embrace-monitor/SKILL.md
```

- [ ] **Step 2: Rename**

```bash
git mv embrace-monitor/SKILL.md embrace-monitor/SKILL.md.tmpl
```

- [ ] **Step 3: Replace each `192.168.10.66` with the halt-and-ask wording**

The exact replacement depends on context. For shell snippets like `./deploy.sh 192.168.10.66`, replace with `./deploy.sh <DEVICE_IP>`. Anywhere prose says "the device at 192.168.10.66", change to "the device (ask the user for `<DEVICE_IP>`; halt if not provided)".

Add a single sentence near the top of the skill body, just under the description block, that establishes the rule once for the whole skill:

```
> **Device IP:** This skill never assumes a default IP. When device access is
> required, ask the user for `<DEVICE_IP>` and halt if they don't provide one.
```

- [ ] **Step 4: Apply path substitutions; verify clean**

```bash
grep -nE '(/opt/(my-buildroot|output-)|~/Projects/(monitor|aplicacao_ac|deploy-ac3)|~/IdeaProjects/AC3_Docs|~/Embrace2(/|_debug/)|~/Documentos/Recursos|192\.168\.)' embrace-monitor/SKILL.md.tmpl
```

Expected: no output.

- [ ] **Step 5: Render and verify**

```bash
./install.sh --render-only
bash tests/test_no_hardcoded_paths.sh 2>&1 | grep embrace-monitor
```

Expected: no line matching `embrace-monitor`.

- [ ] **Step 6: Commit**

```bash
git add embrace-monitor/SKILL.md.tmpl
git commit -m "refactor: embrace-monitor → template; drop default device IP"
```

---

## Task 15: Convert `embrace-firmware`

**Files:**
- Modify: `embrace-firmware/SKILL.md` → `embrace-firmware/SKILL.md.tmpl`

11 path occurrences + IP references.

Replacements:

| Original | Replacement |
|---|---|
| `~/Projects/aplicacao_ac/` | `{{FIRMWARE_DIR}}/` |
| `~/Projects/aplicacao_ac/CMakeLists.txt` etc. | same — driven by the substitution above |
| `~/Projects/monitor/` (any cross-refs) | `{{MONITOR_DIR}}/` |
| `~/IdeaProjects/AC3_Docs/` (any cross-refs) | `{{DOCS_DIR}}/` |
| `192.168.10.66` and `192.168.10.42` | halt-and-ask wording (same approach as Task 14) |

- [ ] **Step 1: Find IP references**

```bash
grep -n '192\.168' embrace-firmware/SKILL.md
```

- [ ] **Step 2: Rename**

```bash
git mv embrace-firmware/SKILL.md embrace-firmware/SKILL.md.tmpl
```

- [ ] **Step 3: Add the device-IP rule sentence near the top of the skill body** (same wording as Task 14).

- [ ] **Step 4: Apply IP replacements** (`./deploy.sh 192.168.10.66` → `./deploy.sh <DEVICE_IP>`, prose adjusted).

- [ ] **Step 5: Apply path substitutions; verify clean**

```bash
grep -nE '(/opt/(my-buildroot|output-)|~/Projects/(monitor|aplicacao_ac|deploy-ac3)|~/IdeaProjects/AC3_Docs|~/Embrace2(/|_debug/)|~/Documentos/Recursos|192\.168\.)' embrace-firmware/SKILL.md.tmpl
```

Expected: no output.

- [ ] **Step 6: Render and verify**

```bash
./install.sh --render-only
bash tests/test_no_hardcoded_paths.sh 2>&1 | grep embrace-firmware
```

Expected: no line matching `embrace-firmware`.

- [ ] **Step 7: Commit**

```bash
git add embrace-firmware/SKILL.md.tmpl
git commit -m "refactor: embrace-firmware → template; drop default device IPs"
```

---

## Task 16: Convert `embrace-buildroot`

**Files:**
- Modify: `embrace-buildroot/SKILL.md` → `embrace-buildroot/SKILL.md.tmpl`

36 path occurrences. Plus:
- **Delete line 115** entirely (one-time migration note: "Migrate `/opt/output-x86` → `/opt/output-x86-full` (one-time, with symlink); bootstrap `/opt/output-x86-pro` from x86-full via `cp -al`."). Renumber subsequent items in that ordered list accordingly.

Replacements:

| Original | Replacement |
|---|---|
| `/opt/my-buildroot` | `{{BUILDROOT_DIR}}` |
| `/opt/output-x86-full` | `{{BUILDROOT_OUT_X86_FULL}}` |
| `/opt/output-x86-pro` | `{{BUILDROOT_OUT_X86_PRO}}` |
| `/opt/output-arm` | `{{BUILDROOT_OUT_ARM}}` |
| `/opt/output-x86` (legacy bare form) | should not survive — see "delete line 115" above |
| `~/Embrace2/` (and all sub-paths under it) | `{{EMBRACE2_DIR}}/` |
| `~/Documentos/Recursos\ Embrace2/` (shell snippets) | `"{{RECURSOS_DIR}}"/` (note the surrounding double quotes — value contains a space) |
| `~/Documentos/Recursos Embrace2/` (prose, no backslash) | `{{RECURSOS_DIR}}/` |

- [ ] **Step 1: Rename**

```bash
git mv embrace-buildroot/SKILL.md embrace-buildroot/SKILL.md.tmpl
```

- [ ] **Step 2: Delete line 115** (and renumber the surrounding `1. ... 5. ... 6. ...` list).

- [ ] **Step 3: Apply path substitutions in this order** (longest-prefix-first to avoid one replacing inside another):

```
/opt/output-x86-full   → {{BUILDROOT_OUT_X86_FULL}}
/opt/output-x86-pro    → {{BUILDROOT_OUT_X86_PRO}}
/opt/output-arm        → {{BUILDROOT_OUT_ARM}}
/opt/my-buildroot      → {{BUILDROOT_DIR}}
~/Embrace2             → {{EMBRACE2_DIR}}
~/Documentos/Recursos\ Embrace2 → "{{RECURSOS_DIR}}"
~/Documentos/Recursos Embrace2  → {{RECURSOS_DIR}}
```

Quote inside shell snippets — every `{{RECURSOS_DIR}}` reference inside a fenced code block must be wrapped in `"..."`.

- [ ] **Step 4: Verify clean**

```bash
grep -nE '(/opt/(my-buildroot|output-)|~/Projects/(monitor|aplicacao_ac|deploy-ac3)|~/IdeaProjects/AC3_Docs|~/Embrace2(/|_debug/)|~/Documentos/Recursos|192\.168\.)' embrace-buildroot/SKILL.md.tmpl
```

Expected: no output.

- [ ] **Step 5: Render and verify**

```bash
./install.sh --render-only
bash tests/test_no_hardcoded_paths.sh 2>&1 | grep embrace-buildroot
```

Expected: no line matching `embrace-buildroot`.

- [ ] **Step 6: Skim the rendered output**

```bash
less .rendered/embrace-buildroot/SKILL.md
```

Confirm: no `{{...}}` tokens remain, list numbering after the deleted line 115 is still consecutive, and the `"{{RECURSOS_DIR}}"` quoting expanded to a properly-quoted absolute path inside shell snippets.

- [ ] **Step 7: Commit**

```bash
git add embrace-buildroot/SKILL.md.tmpl
git commit -m "refactor: embrace-buildroot → template; drop legacy /opt/output-x86 migration note"
```

---

## Task 17: Convert `analyze-core-dump`

**Files:**
- Modify: `analyze-core-dump/SKILL.md` → `analyze-core-dump/SKILL.md.tmpl`

18 path occurrences. Plus these targeted edits:

1. **Line 159** (x86 gdb path table row): the `gdb` column currently reads `/opt/output-x86/host/bin/x86_64-buildroot-linux-gnu-gdb`. Change to `{{BUILDROOT_OUT_X86_FULL}}/host/bin/x86_64-buildroot-linux-gnu-gdb`. The sysroot column already reads `/opt/output-x86-full/host/x86_64-buildroot-linux-gnu/sysroot`; that becomes `{{BUILDROOT_OUT_X86_FULL}}/host/x86_64-buildroot-linux-gnu/sysroot` like the rest.
2. **Line ~140**: `~/Documentos/Recursos\ Embrace2/analisa-coredump.sh` → `{{SKILLS_REPO}}/resources/analisa-coredump.sh`.
3. **Anywhere referencing `guia-coredump.md`**: `~/Documentos/Recursos Embrace2/guia-coredump.md` → `{{SKILLS_REPO}}/resources/guia-coredump.md`.

Other mechanical replacements:

| Original | Replacement |
|---|---|
| `~/Embrace2_debug/...` | `{{EMBRACE2_DEBUG_DIR}}/...` |
| `~/Projects/deploy-ac3/` | `{{DEPLOY_AC3_DIR}}/` |
| `/opt/output-arm/host/bin/...` etc. | `{{BUILDROOT_OUT_ARM}}/host/bin/...` |

- [ ] **Step 1: Rename**

```bash
git mv analyze-core-dump/SKILL.md analyze-core-dump/SKILL.md.tmpl
```

- [ ] **Step 2: Apply the three targeted edits above** (line 159 gdb fix; bundled-script references; bundled-guide references).

- [ ] **Step 3: Apply the mechanical path substitutions.**

- [ ] **Step 4: Verify clean**

```bash
grep -nE '(/opt/(my-buildroot|output-)|~/Projects/(monitor|aplicacao_ac|deploy-ac3)|~/IdeaProjects/AC3_Docs|~/Embrace2(/|_debug/)|~/Documentos/Recursos|192\.168\.)' analyze-core-dump/SKILL.md.tmpl
```

Expected: no output.

- [ ] **Step 5: Render and verify**

```bash
./install.sh --render-only
bash tests/test_no_hardcoded_paths.sh
```

Expected: now **all 7 skills clean** — `0 failed`.

- [ ] **Step 6: Inspect the rendered file**

```bash
grep -n 'analisa-coredump\|guia-coredump' .rendered/analyze-core-dump/SKILL.md
```

Expected: both references point to absolute paths under the repo's `resources/` dir.

- [ ] **Step 7: Commit**

```bash
git add analyze-core-dump/SKILL.md.tmpl
git commit -m "refactor: analyze-core-dump → template; bundle script+guide refs; fix legacy gdb path"
```

---

## Task 18: Run the full test suite

- [ ] **Step 1: Run everything**

```bash
./tests/run-all.sh
```

Expected output ends with `OK` for every `test_*.sh`, exit code 0.

- [ ] **Step 2: Manually spot-check a rendered skill**

```bash
diff <(sed -n '1,50p' embrace-buildroot/SKILL.md.tmpl) \
     <(sed -n '1,50p' .rendered/embrace-buildroot/SKILL.md)
```

Confirm: the rendered version has the `AUTO-GENERATED` header at the top and every `{{VAR}}` was substituted to an absolute path.

- [ ] **Step 3: No commit (verification only)**

---

## Task 19: Rewrite the README

**Files:**
- Modify: `README.md`

Three sections change. Open `README.md` and apply each edit below verbatim.

- [ ] **Step 1: Replace the "Prerequisites — local paths the skills assume" section**

Locate the section starting `## Prerequisites — local paths the skills assume`. Replace the entire section (heading, prose, table, and the closing "if your machine uses different paths" paragraph) with:

```markdown
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
```

- [ ] **Step 2: Replace the "Install" section**

Locate the three install options (Option 1 / 2 / 3) and replace the whole `## Install` section through to (but not including) `## Verify` with:

```markdown
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
```

- [ ] **Step 3: Replace the "Updates" section**

Replace `## Updates` through to (but not including) `## Uninstall` with:

```markdown
## Updates

```bash
cd ~/Projects/embrace-skills
git pull
./install.sh --render-only
```

If you edited `~/.config/embrace-skills/paths.conf`, run `./install.sh --reconfigure` instead — same effect, clearer in command history.
```

- [ ] **Step 4: Replace the "Uninstall" section**

Replace the `## Uninstall` section with:

```markdown
## Uninstall

```bash
cd ~/Projects/embrace-skills
./uninstall.sh                  # default: global
./uninstall.sh --mode=per-repo  # if you installed with --mode=per-repo
```

This only removes symlinks pointing at `.rendered/` under this repo — unrelated symlinks in `~/.claude/skills/` are left alone.
```

- [ ] **Step 5: Verify the README still mentions the manual `/embrace-docs` invocation rule** (existing Usage section should be untouched). If the example commands in §Usage reference any of the old hardcoded paths, change them to the variable form (e.g. `cd $FIRMWARE_DIR`).

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: README — render-at-install flow, variable table, new install/update commands"
```

---

## Task 20: End-to-end verification on the maintainer's machine

This is a manual smoke test on the real machine — not a scripted test.

- [ ] **Step 1: Fresh global install**

```bash
cd ~/Projects/embrace-skills
./uninstall.sh 2>/dev/null || true        # in case an old v1 symlink set is present
./install.sh --mode=global
ls -l ~/.claude/skills/ | grep -E '^l.*embrace-skills'
```

Expected: 7 symlinks, each pointing at `~/Projects/embrace-skills/.rendered/<name>`.

- [ ] **Step 2: Spot-check that Claude loads them**

In a new Claude Code session, ask:

```
list available skills, only the embrace-* and analyze-core-dump ones
```

Expected: all 7 listed by name. If `description:` frontmatter went through the template engine cleanly, they should look identical to today's set.

- [ ] **Step 3: Spot-check a rendered body**

```bash
head -40 ~/.claude/skills/embrace-buildroot/SKILL.md | grep -E '(\{\{|192\.168\.|/opt/output-x86 )'
```

Expected: no output (no unresolved tokens, no legacy IP, no legacy x86 dir).

- [ ] **Step 4: Override flow**

```bash
mkdir -p ~/.config/embrace-skills
echo 'FIRMWARE_DIR="$HOME/Projects/aplicacao_ac"' > ~/.config/embrace-skills/paths.conf
./install.sh --reconfigure
head -1 .rendered/add-firmware-module/SKILL.md   # AUTO-GENERATED header
grep -c FIRMWARE_DIR .rendered/add-firmware-module/SKILL.md   # should be 0 — all substituted
grep "$HOME/Projects/aplicacao_ac" .rendered/add-firmware-module/SKILL.md | head -1
```

Expected: `0` and at least one line showing the substituted path.

- [ ] **Step 5: Uninstall round-trip**

```bash
./uninstall.sh
ls ~/.claude/skills/ | grep -E '(embrace-|analyze-core-dump|firmware-module|add-firmware)' || echo "all cleaned"
./install.sh
ls -l ~/.claude/skills/ | grep -E '^l.*embrace-skills' | wc -l   # should be 7
```

Expected: `all cleaned`, then `7`.

- [ ] **Step 6: No code changes** — this task is verification only. If anything failed, file follow-up tasks before declaring done.

---

## Self-review checklist (done before handoff)

- **Spec coverage:**
  - 11 host paths in `paths.defaults.conf` (Task 2) ✓
  - `paths.conf` / `paths.local.conf` layering with defaults (Task 4) ✓
  - `install.sh` with `--mode=global`, `--mode=per-repo`, `--render-only`, `--reconfigure` (Tasks 4–6) ✓
  - `uninstall.sh` (Task 7) ✓
  - `.gitignore` for `.rendered/`, `paths.conf`, `paths.local.conf` (Task 8) ✓
  - Bundled `analisa-coredump.sh` and `guia-coredump.md` in `resources/` (Task 9) ✓
  - 7 skill template conversions (Tasks 11–17) ✓
  - Legacy `/opt/output-x86` reference fixed + migration note deleted (Tasks 16, 17) ✓
  - Default device IP removed; halt-and-ask wording (Tasks 14, 15) ✓
  - README rewrite for Prerequisites/Install/Updates/Uninstall (Task 19) ✓
  - `{{SKILLS_REPO}}` exposed by renderer (Task 4) ✓
  - AUTO-GENERATED header on rendered files (Task 4) ✓
  - End-to-end smoke (Task 20) ✓
- **Placeholders:** no TODOs / TBDs / "implement appropriately".
- **Type consistency:** `render_file` signature is `<in> <out>` in both definition (Task 3) and uses (Task 4); `EMBRACE_SKILLS_HOME` env var named identically across install.sh (Task 4), uninstall.sh (Task 7), and the test that sets it (Tasks 5, 7); variable names in the defaults file match the templated tokens exactly (cross-checked against the replacement tables in Tasks 11–17); per-repo mapping in install.sh (Task 6) matches the one documented in README (Task 19).

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-11-configurable-paths.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
