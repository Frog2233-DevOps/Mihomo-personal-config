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
MIHOMO="${MIHOMO:-mihomo}"
MIHOMO_SMART="${MIHOMO_SMART:-mihomo-smart}"

cd "$ROOT"

rc=0

echo "=== 1. mihomo -t ==="
for f in RU-Mihomo.yaml RU-Mihomo-lite.yaml; do
  if command -v "$MIHOMO" >/dev/null 2>&1 || [ -x "$MIHOMO" ]; then
    if out="$("$MIHOMO" -t -f "$f" -d . 2>&1)"; then
      echo "  OK   $f"
    else
      echo "  FAIL $f"
      echo "$out" | tail -n 5 | sed 's/^/       /'
      rc=1
    fi
  else
    echo "  SKIP $f (no mihomo binary: set MIHOMO=...)"
  fi
done

if command -v "$MIHOMO_SMART" >/dev/null 2>&1 || [ -x "$MIHOMO_SMART" ]; then
  if out="$("$MIHOMO_SMART" -t -f RU-Mihomo-smart.yaml -d . 2>&1)"; then
    echo "  OK   RU-Mihomo-smart.yaml"
  else
    echo "  FAIL RU-Mihomo-smart.yaml"
    echo "$out" | tail -n 5 | sed 's/^/       /'
    rc=1
  fi
else
  echo "  SKIP RU-Mihomo-smart.yaml (no smart core: set MIHOMO_SMART=...)"
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
