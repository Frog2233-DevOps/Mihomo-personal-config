#!/usr/bin/env bash
# =============================================================================
#  selftest.sh - check that the configuration is still consistent
# =============================================================================
#  Run it after every change and before every commit:
#      ./scripts/selftest.sh
#
#  What it checks:
#    1. mihomo -t on every config (main, lite, smart)
#    2. the filters: the noise part of foreign-filter must be identical to
#       noise-filter, otherwise an LTE node can slip into an automatic group
#    3. every group used in the rules exists
#    4. every rule-provider file exists in ruleset/
#    5. the generated variants really are generated variants
#
#  Environment variables:
#      MIHOMO       - path to the mihomo binary     (default: mihomo)
#      MIHOMO_SMART - path to the smart core binary (default: mihomo-smart)
# =============================================================================
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

# Find the cores: the PATH first, then the repository root (the CI downloads
# them there). The script must not depend on being executable itself.
find_core() { # find_core <name>
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
MIHOMO_SMART="$(find_core mihomo-smart "${MIHOMO_SMART:-}")"

cd "$ROOT"

rc=0

echo "=== 1. mihomo -t ==="
for f in RU-Mihomo.yaml RU-Mihomo-lite.yaml; do
  if [ -n "$MIHOMO" ] && [ -x "$MIHOMO" ]; then
    if out="$("$MIHOMO" -t -f "$f" -d . 2>&1)"; then
      echo "  OK   $f"
    else
      echo "  FAIL $f"
      echo "$out" | tail -n 5 | sed 's/^/       /'
      rc=1
    fi
  else
    echo "  SKIP $f (no mihomo binary: put it in the PATH or in the repo root)"
  fi
done

if [ -n "$MIHOMO_SMART" ] && [ -x "$MIHOMO_SMART" ]; then
  if out="$("$MIHOMO_SMART" -t -f RU-Mihomo-smart.yaml -d . 2>&1)"; then
    echo "  OK   RU-Mihomo-smart.yaml"
  else
    echo "  FAIL RU-Mihomo-smart.yaml"
    echo "$out" | tail -n 5 | sed 's/^/       /'
    rc=1
  fi
else
  echo "  SKIP RU-Mihomo-smart.yaml (no smart core: put it in the PATH or in the repo root)"
fi

echo
echo "=== 2-6. consistency ==="
python3 "$DIR/selftest.py" || rc=1

echo
if [ "$rc" = "0" ]; then
  echo "SELFTEST OK"
else
  echo "SELFTEST FAILED"
fi
exit $rc
