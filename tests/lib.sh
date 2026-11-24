#!/usr/bin/env sh
# Shared helpers for the test suite. No external modules, POSIX shell only.

PASS=0
FAIL=0
SKIP=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()      { PASS=$((PASS + 1)); printf '  OK   %s\n' "$1"; }
bad()     { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
skip()    { SKIP=$((SKIP + 1)); printf '  SKIP %s\n' "$1"; }

# check <description> <command...>
check() {
  desc=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

# has <file> <fixed string>
has() {
  if grep -qF -- "$2" "$1" 2>/dev/null; then ok "$1 contains: $2"; else bad "$1 missing: $2"; fi
}

# lacks <file> <fixed string>
lacks() {
  if grep -qF -- "$2" "$1" 2>/dev/null; then bad "$1 still contains: $2"; else ok "$1 has no: $2"; fi
}

summary() {
  printf '\n[%s] pass=%d fail=%d skip=%d\n' "$(basename "$0")" "$PASS" "$FAIL" "$SKIP"
  [ "$FAIL" -eq 0 ]
}

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMPDIR_TEST="${TMPDIR:-/tmp}/mihomo-tests.$$"
mkdir -p "$TMPDIR_TEST"
trap 'rm -rf "$TMPDIR_TEST"' EXIT
