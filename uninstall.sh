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
