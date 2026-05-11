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
