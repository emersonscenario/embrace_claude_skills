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
