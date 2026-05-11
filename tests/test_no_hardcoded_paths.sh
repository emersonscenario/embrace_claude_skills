#!/usr/bin/env bash
# tests/test_no_hardcoded_paths.sh
# Renders every skill template with SENTINEL values for each path variable,
# then scans the rendered output for any literal retired path. The sentinels
# guarantee that production literals (e.g. /opt/my-buildroot, ~/Projects/...,
# 192.168.10.66) appear ONLY if a template forgot to use {{VAR}}.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
source "$HERE/lib.sh"

SANDBOX=$(mk_sandbox)
trap 'rm -rf "$SANDBOX"' EXIT

# Build a tiny mirror of the repo in the sandbox.
SANDREPO="$SANDBOX/repo"
mkdir -p "$SANDREPO/lib"
cp "$REPO/install.sh"     "$SANDREPO/"
chmod +x "$SANDREPO/install.sh"
cp "$REPO/lib/render.sh"  "$SANDREPO/lib/"
# resources/ may or may not exist depending on task order — copy if present.
[ -d "$REPO/resources" ] && cp -a "$REPO/resources" "$SANDREPO/resources"

# Sentinel paths.defaults.conf — every var resolves to a string that cannot
# overlap with any real retired path.
cat >"$SANDREPO/paths.defaults.conf" <<'EOF'
BUILDROOT_DIR="__BUILDROOT_DIR__"
BUILDROOT_OUT_X86_FULL="__BUILDROOT_OUT_X86_FULL__"
BUILDROOT_OUT_X86_PRO="__BUILDROOT_OUT_X86_PRO__"
BUILDROOT_OUT_ARM="__BUILDROOT_OUT_ARM__"
MONITOR_DIR="__MONITOR_DIR__"
FIRMWARE_DIR="__FIRMWARE_DIR__"
DEPLOY_AC3_DIR="__DEPLOY_AC3_DIR__"
DOCS_DIR="__DOCS_DIR__"
EMBRACE2_DIR="__EMBRACE2_DIR__"
EMBRACE2_DEBUG_DIR="__EMBRACE2_DEBUG_DIR__"
RECURSOS_DIR="__RECURSOS_DIR__"
EOF

# Mirror every <skill>/SKILL.md.tmpl into the sandbox.
shopt -s nullglob
TMPLS=("$REPO"/*/SKILL.md.tmpl)
for t in "${TMPLS[@]}"; do
    skill=$(basename "$(dirname "$t")")
    mkdir -p "$SANDREPO/$skill"
    cp "$t" "$SANDREPO/$skill/SKILL.md.tmpl"
done

# Sandboxed HOME so any real ~/.config/embrace-skills/paths.conf can't leak in.
FAKEHOME="$SANDBOX/home"
mkdir -p "$FAKEHOME"
EMBRACE_SKILLS_HOME="$FAKEHOME" bash "$SANDREPO/install.sh" --render-only >/dev/null 2>&1

shopt -s nullglob
RENDERED=("$SANDREPO"/.rendered/*/SKILL.md)
if [ "${#RENDERED[@]}" -eq 0 ]; then
    if [ "${#TMPLS[@]}" -eq 0 ]; then
        # No templates yet (Tasks 11-17 haven't run) — accept as a known pending state.
        fail "no SKILL.md.tmpl files in repo yet (Tasks 11-17 pending)"
    else
        fail "no rendered SKILL.md files were produced from ${#TMPLS[@]} template(s)"
    fi
    summary; exit
fi

# Patterns that must NOT appear in any rendered SKILL.md.
# Tilde-prefixed paths cannot survive correct templating (paths.defaults.conf
# uses $HOME which expands at source-time). Production /opt and IP literals
# cannot survive because the sandbox conf uses sentinels.
PATTERNS=(
    "/opt/my-buildroot"
    "/opt/output-x86-full"
    "/opt/output-x86-pro"
    "/opt/output-arm"
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

# Special-case: bare legacy /opt/output-x86 must NOT appear, but the substring
# also occurs inside /opt/output-x86-full and /opt/output-x86-pro. Use a regex
# that matches /opt/output-x86 NOT followed by a hyphen.
LEGACY_X86_RE='/opt/output-x86([^-]|$)'

for f in "${RENDERED[@]}"; do
    skill=$(basename "$(dirname "$f")")
    hit=0
    for p in "${PATTERNS[@]}"; do
        if grep -qF -- "$p" "$f"; then
            fail "$skill still contains [$p]"
            hit=1
            break
        fi
    done
    if [ "$hit" -eq 0 ] && grep -qE -- "$LEGACY_X86_RE" "$f"; then
        fail "$skill still contains legacy /opt/output-x86 (bare, non -full/-pro)"
    fi
done

summary
