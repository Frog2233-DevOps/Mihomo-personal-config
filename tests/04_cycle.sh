#!/usr/bin/env bash
# Full build -> deploy -> apply -> check cycle against a real router.
# Enable with ROUTER_HOST=... ROUTER_PORT=... [SECRET=...].
set -u
. "$(dirname "$0")/lib.sh"
cd "$ROOT"

if [ -z "${ROUTER_HOST:-}" ]; then
  skip "router cycle (set ROUTER_HOST and ROUTER_PORT to enable)"
  summary
  exit 0
fi

ROUTER_PORT="${ROUTER_PORT:-22}"
ROUTER_USER="${ROUTER_USER:-root}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $ROUTER_PORT"
[ -f "$SSH_KEY" ] && SSH="$SSH -i $SSH_KEY"

section "1. deploy with a non-default port"
if ROUTER_HOST="$ROUTER_HOST" ROUTER_PORT="$ROUTER_PORT" ROUTER_USER="$ROUTER_USER" \
   SSH_KEY="$SSH_KEY" APPLY=none bash scripts/deploy.sh >"$TMPDIR_TEST/deploy.log" 2>&1; then
  ok "deploy.sh completed"
else
  bad "deploy.sh failed: $(tail -5 "$TMPDIR_TEST/deploy.log")"
fi

section "2. the router layout is complete"
layout=$($SSH "$ROUTER_USER@$ROUTER_HOST" \
  'find /etc/openclash -maxdepth 2 -type f | sort' 2>/dev/null)
for p in config/RU-Mihomo.yaml lists/custom-domains.list backup/RU-Mihomo.conf \
         scripts/build-ruleset.sh scripts/update-rulesets.sh scripts/apply-rulesets.sh \
         scripts/check-groups.sh; do
  if printf '%s\n' "$layout" | grep -q "/etc/openclash/$p\$"; then ok "$p deployed"; else bad "$p missing on router"; fi
done
n=$(printf '%s\n' "$layout" | grep -c '/ruleset/.*\.mrs$')
if [ "$n" -eq 28 ]; then ok "28 rule-sets deployed"; else bad "$n rule-sets deployed (expected 28)"; fi

section "3. apply-rulesets check sees real rule providers"
if [ -n "${SECRET:-}" ]; then
  out=$($SSH "$ROUTER_USER@$ROUTER_HOST" \
    "APPLY=check SECRET='$SECRET' sh /etc/openclash/scripts/apply-rulesets.sh" 2>/dev/null)
  if printf '%s\n' "$out" | grep -q 'rule-providers, .* rules in total'; then
    ok "API reports rule providers: $(printf '%s\n' "$out" | tail -1)"
  else
    bad "apply-rulesets check failed: $(printf '%s\n' "$out" | head -3)"
  fi
else
  skip "apply check (set SECRET)"
fi

section "4. check-groups rejects a bad secret"
if [ -n "${SECRET:-}" ]; then
  $SSH "$ROUTER_USER@$ROUTER_HOST" 'SECRET=definitely-wrong sh /etc/openclash/scripts/check-groups.sh' \
    >"$TMPDIR_TEST/cg.bad" 2>&1
  if grep -q 'did not return the proxy list' "$TMPDIR_TEST/cg.bad"; then ok "401 is rejected"; else bad "401 accepted as a group list"; fi
  if grep -q 'NOT FOUND' "$TMPDIR_TEST/cg.bad"; then bad "false NOT FOUND on 401"; else ok "no false NOT FOUND"; fi
else
  skip "check-groups auth test (set SECRET)"
fi

section "5. build-ruleset byte counter under busybox"
if [ -n "${SECRET:-}" ]; then
  # The counter is printed by build-ruleset.sh itself; check the code on the
  # router is the fixed version, not one that reports "Bytes: 0".
  if $SSH "$ROUTER_USER@$ROUTER_HOST" 'grep -q "wc -c" /etc/openclash/scripts/build-ruleset.sh' 2>/dev/null; then
    ok "router has the busybox-safe counter"
  else
    bad "router build script still uses stat -c%s"
  fi
else
  skip "busybox counter check"
fi

summary
