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
