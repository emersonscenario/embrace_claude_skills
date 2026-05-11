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
    *)
        echo "install.sh: unknown mode: $MODE" >&2
        exit 2
        ;;
esac
