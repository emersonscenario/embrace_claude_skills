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
