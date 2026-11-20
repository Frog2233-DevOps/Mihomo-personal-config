#!/usr/bin/env bash
# =============================================================================
#  make-lite.sh - build RU-Mihomo-lite.yaml from RU-Mihomo.yaml
# =============================================================================
#  The lite variant is the full config WITHOUT the ad-blocking rule-set.
#  Reason: anti-AD is 101 113 domains and costs about 4 MB of RAM. On a router
#  with 128 MB that matters. The price: ads are not blocked.
#
#  The lite file is generated, not maintained by hand - this keeps it from
#  drifting away from the full config.
#
#  Usage: ./make-lite.sh
# =============================================================================
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/RU-Mihomo.yaml"
DST="$DIR/RU-Mihomo-lite.yaml"

[ -f "$SRC" ] || { echo "ERROR: $SRC not found"; exit 1; }

python3 - "$SRC" "$DST" <<'PYEOF'
import re, sys

src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()

# 1. Drop the antiad rule-provider block.
text = re.sub(
    r"(?m)^  # --- Ads ---\n(?:  #.*\n)*  antiad:\n(?:    .*\n)+",
    "", text)

# 2. Drop the antiad rule and note why it is gone.
text = text.replace(
    "  # 2. Ads.\n  - RULE-SET,antiad,REJECT\n",
    "  # 2. Ads - DISABLED in the lite variant (saves about 4 MB of RAM).\n")

# 3. Adjust the header note.
text = text.replace(
    "#  Subscription: exactly one.",
    "#  LITE VARIANT: ad blocking is disabled here, see make-lite.sh.\n"
    "#\n"
    "#  Subscription: exactly one.")

open(dst, "w", encoding="utf-8").write(text)
print(f"written: {dst}")
PYEOF

# Sanity check: the lite file must not reference antiad anymore.
if grep -q "antiad" "$DST"; then
  echo "ERROR: antiad still referenced in $DST"
  exit 1
fi

echo "OK: lite variant has no antiad references"
