#!/usr/bin/env bash
# =============================================================================
#  fix-exec.sh - mark the scripts as executable and refresh the workflows
# =============================================================================
#  Why this is needed:
#    Files that are uploaded through the GitHub API are created without the
#    executable bit (mode 100644). The workflows then die with
#    "Permission denied" (exit 126).
#
#  What it does:
#    1. sets the executable bit in the git index (100755)
#    2. copies the workflows from automation/ into .github/workflows/
#    3. prints the commit command - the commit and the push are left to you
#
#  Usage:  bash scripts/fix-exec.sh
# =============================================================================
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
cd "$ROOT"

echo "=== 1. the executable bit in the index ==="
git update-index --add --chmod=+x scripts/*.sh scripts/*.py
git ls-files -s scripts/ | awk '{printf "  %s  %s\n", $1, $4}'

echo
echo "=== 2. the workflows ==="
if [ -d automation ] && [ -d .github/workflows ]; then
  cp automation/*.yml .github/workflows/
  echo "  automation/*.yml -> .github/workflows/"
else
  echo "  skipped: automation/ or .github/workflows/ is missing"
fi

echo
echo "=== 3. commit ==="
echo "  git commit -m \"chore: exec bit for the scripts, hardened workflows\""
echo "  git push"
