#!/usr/bin/env bash
# Workflow consistency: copies, triggers, and the CI entry point for tests.
set -u
. "$(dirname "$0")/lib.sh"
cd "$ROOT"

section "1. automation/ and .github/workflows/ are byte-identical"
for f in rulesets.yml validate.yml; do
  if cmp -s "automation/$f" ".github/workflows/$f"; then ok "$f copies match"; else bad "$f copies drifted"; fi
done

section "2. the rebuild workflow still has its guard and the apply step"
has .github/workflows/rulesets.yml "github.event_name != 'push' || github.actor != 'github-actions[bot]'"
has .github/workflows/rulesets.yml 'APPLY: "reload"'
has .github/workflows/rulesets.yml 'apply-rulesets.sh'
has .github/workflows/rulesets.yml 'contents: write'

section "3. validate workflow runs the full test suite"
has .github/workflows/validate.yml 'tests/run-all.sh'
has automation/validate.yml 'tests/run-all.sh'

section "4. YAML is at least structurally plausible"
python3 - "$ROOT" <<'PY' || exit 1
import sys, os
root = sys.argv[1]
bad = []
for d in ('.github/workflows', 'automation'):
    for name in os.listdir(os.path.join(root, d)):
        if not name.endswith('.yml'):
            continue
        text = open(os.path.join(root, d, name), encoding='utf-8').read()
        for key in ('name:', 'on:', 'jobs:', 'runs-on:', 'steps:'):
            if key not in text:
                bad.append('%s/%s misses %s' % (d, name, key))
if bad:
    print('  FAIL ' + '; '.join(bad))
    sys.exit(1)
print('  OK   workflow structure')
PY

summary
