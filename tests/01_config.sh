#!/usr/bin/env bash
# Config validation: real core, consistency, generated variants, rule order.
set -u
. "$(dirname "$0")/lib.sh"
cd "$ROOT"

section "1. mihomo -t on every config"
MIHOMO="${MIHOMO:-}"
if [ -n "$MIHOMO" ] && [ -x "$MIHOMO" ]; then
  :
elif command -v mihomo >/dev/null 2>&1; then
  MIHOMO=$(command -v mihomo)
elif [ -x "$ROOT/mihomo" ]; then
  MIHOMO="$ROOT/mihomo"
else
  MIHOMO=""
fi
if [ -n "$MIHOMO" ]; then
  for f in RU-Mihomo.yaml RU-Mihomo-lite.yaml; do
    if "$MIHOMO" -t -f "$f" -d . >/tmp/mihomo-t.$$ 2>&1; then ok "$f passes mihomo -t"
    else bad "$f fails mihomo -t: $(tail -3 /tmp/mihomo-t.$$)"; fi
  done
else
  skip "mihomo -t (no core: set MIHOMO=...)"
fi
rm -f /tmp/mihomo-t.$$

section "2. the repository selftest"
check "scripts/selftest.py passes" python3 scripts/selftest.py

section "3. no forbidden config patterns"
# The YAML explains the forbidden patterns in comments, so check code only.
code() { awk '$0 !~ /^[[:space:]]*#/' "$1"; }
if code RU-Mihomo.yaml | grep -qF 'geosite:category-ru'; then bad "geosite policy in code"; else ok "no geosite policy in code"; fi
if code RU-Mihomo.yaml | grep -qF 'external-ui-url'; then bad "external-ui-url in code"; else ok "no external-ui-url in code"; fi
if code RU-Mihomo.yaml | grep -qF 'behavior: classical'; then bad "classical behavior in code"; else ok "no classical behavior in code"; fi
if code RU-Mihomo.yaml | grep -qF 'rule-set:ru-domains'; then ok "local DNS rule-set present"; else bad "local DNS rule-set missing"; fi
if code RU-Mihomo.yaml | grep -qF 'geo-auto-update: false'; then ok "geo auto update off"; else bad "geo auto update on"; fi
has RU-Mihomo.yaml "secret: CHANGE_ME"
has RU-Mihomo.conf "DASHBOARD_PASSWORD = CHANGE_ME"
# A top level proxies: block would be rewritten by OpenClash and share the
# YAML anchor, breaking all service groups.
if grep -q '^proxies:' RU-Mihomo.yaml; then bad "top level proxies: block"; else ok "no top level proxies: block"; fi

section "4. rule order (measured, see docs/DESIGN.md)"
order=$(awk '/^rules:/{f=1;next} f && /^  - RULE-SET,/{split($2,a,","); print a[2]}' RU-Mihomo.yaml)
pos() { printf '%s\n' "$order" | grep -nFx "$1" | head -1 | cut -d: -f1; }
for pair in 'custom-domains:antiad' 'antiad:telegram' 'telegram:rkn-blocked' 'rkn-blocked:ru-domains'; do
  a=${pair%%:*}; b=${pair##*:}
  pa=$(pos "$a"); pb=$(pos "$b")
  if [ -n "$pa" ] && [ -n "$pb" ] && [ "$pa" -lt "$pb" ]; then ok "rule $a before $b"; else bad "rule order $a -> $b ($pa vs $pb)"; fi
done

section "5. every rule-provider file exists"
count=0; missing=0
while read -r p; do
  count=$((count + 1))
  [ -f "${p#./}" ] || { bad "missing $p"; missing=$((missing + 1)); }
done < <(awk '/^rule-providers:/{f=1;next} /^proxy-groups:/{f=0} f && /path:/{print $2}' RU-Mihomo.yaml)
if [ "$missing" -eq 0 ]; then ok "all $count rule-set files exist"; fi

section "6. generated variants are reproducible"
cp RU-Mihomo-lite.yaml "$TMPDIR_TEST/lite.before"
cp RU-Mihomo-smart.yaml "$TMPDIR_TEST/smart.before"
bash scripts/make-lite.sh >/dev/null 2>&1 || bad "make-lite.sh failed"
bash scripts/make-smart.sh >/dev/null 2>&1 || bad "make-smart.sh failed"
cmp -s "$TMPDIR_TEST/lite.before" RU-Mihomo-lite.yaml && ok "lite variant unchanged" || bad "lite variant drifted"
cmp -s "$TMPDIR_TEST/smart.before" RU-Mihomo-smart.yaml && ok "smart variant unchanged" || bad "smart variant drifted"

section "7. empty custom list still produces a valid rule-set"
if grep -q 'custom-domains.invalid' scripts/build-ruleset.sh; then ok "empty-list placeholder is present"; else bad "empty-list placeholder missing"; fi

summary
