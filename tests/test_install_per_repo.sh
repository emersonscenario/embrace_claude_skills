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
