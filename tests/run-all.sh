#!/usr/bin/env bash
# Run every test script. Exits non-zero if any of them fails.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "$DIR"/[0-9]*.sh; do
  echo
  echo "############################################################"
  echo "### $(basename "$t")"
  echo "############################################################"
  bash "$t" || rc=1
done
echo
if [ "$rc" = "0" ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit "$rc"
