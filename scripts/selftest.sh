#!/usr/bin/env bash
# =============================================================================
#  selftest.sh - check that the mixomo configuration is still consistent
# =============================================================================
#  Run it after every change and before every commit:
#      ./scripts/selftest.sh
#
#  What it checks:
#    1. mihomo -t on the config of the scheme
#    2. the scripts that go to the router are POSIX sh (busybox ash on the
#       router has no bash) and shellcheck is happy with them
#    3. the consistency of the config, of the groups, of the rule-sets and
#       of the state of MagiTrickle
#
#  Environment variables:
#      MIHOMO      - path to the mihomo binary  (default: mihomo)
#      SHELLCHECK  - path to the shellcheck binary (default: shellcheck)
# =============================================================================
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

# Find the core: the PATH first, then the repository root (the CI downloads
# it there). The script must not depend on being executable itself.
find_core() { # find_core <name> <override>
  if [ -n "$2" ] && [ -x "$2" ]; then
    printf '%s' "$2"; return 0
  fi
  if command -v "$1" >/dev/null 2>&1; then
    command -v "$1"; return 0
  fi
  if [ -x "$ROOT/$1" ]; then
    printf '%s' "$ROOT/$1"; return 0
  fi
  printf ''
}

MIHOMO="$(find_core mihomo "${MIHOMO:-}")"

cd "$ROOT" || exit 1

rc=0

echo "=== 1. mihomo -t ==="
f=RU-Mihomo-mixomo.yaml
if [ -n "$MIHOMO" ] && [ -x "$MIHOMO" ]; then
  # The layout of mixomo: the rule-sets live in rule-files/ and the provider
  # in proxy-providers/, the core is started with -d /etc/mihomo.
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/rule-files" "$tmp/proxy-providers"
  cp ruleset/*.mrs "$tmp/rule-files/" 2>/dev/null || true
  if out="$("$MIHOMO" -t -f "$f" -d "$tmp" 2>&1)"; then
    echo "  OK   $f"
  else
    echo "  FAIL $f"
    echo "$out" | tail -n 5 | sed 's/^/       /'
    rc=1
  fi
  rm -rf "$tmp"
else
  echo "  SKIP $f (no mihomo binary: put it in the PATH or in the repo root)"
fi

echo
echo "=== 2. the scripts that go to the router ==="
# Everything in scripts/ except this one goes to the router and runs there
# under busybox ash: bash syntax is not allowed.
router_scripts=""
for f in scripts/*.sh; do
  [ "$f" = "scripts/selftest.sh" ] && continue
  router_scripts="$router_scripts $f"
done
for f in $router_scripts scripts/*.init; do
  [ -f "$f" ] || continue
  if sh -n "$f" 2>/dev/null; then
    echo "  OK   $f is POSIX sh"
  else
    echo "  FAIL $f is not POSIX sh"
    sh -n "$f" 2>&1 | head -n 3 | sed 's/^/       /'
    rc=1
  fi
done

SHELLCHECK="${SHELLCHECK:-shellcheck}"
if command -v "$SHELLCHECK" >/dev/null 2>&1; then
  for f in $router_scripts scripts/*.init; do
    [ -f "$f" ] || continue
    if out="$("$SHELLCHECK" -s sh "$f" 2>&1)"; then
      echo "  OK   shellcheck $f"
    else
      echo "  FAIL shellcheck $f"
      echo "$out" | head -n 10 | sed 's/^/       /'
      rc=1
    fi
  done
else
  echo "  SKIP shellcheck is not installed (pip install shellcheck-py)"
fi

echo
echo "=== 3. consistency ==="
python3 "$DIR/selftest.py" || rc=1

echo
if [ "$rc" = "0" ]; then
  echo "SELFTEST OK"
else
  echo "SELFTEST FAILED"
fi
exit $rc
