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
