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
