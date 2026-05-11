#!/usr/bin/env bash
# tests/run-all.sh — runs every tests/test_*.sh in the same dir.
set -u
cd "$(dirname "$0")"
overall_fail=0
for t in test_*.sh; do
    [ -f "$t" ] || continue
    echo "==> $t"
    if bash "$t"; then
        echo "  OK"
    else
        echo "  FAIL"
        overall_fail=1
    fi
done
exit "$overall_fail"
