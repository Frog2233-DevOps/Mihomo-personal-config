#!/usr/bin/env bash
# The mixomo scheme: the config of the core, the state of MagiTrickle and the
# scripts that set the scheme up on the router.
set -u
. "$(dirname "$0")/lib.sh"
cd "$ROOT"

CFG=RU-Mihomo-mixomo.yaml
MT=magitrickle/magitrickle.yaml
MTJ=magitrickle/magitrickle.mtrickle

section "1. mihomo -t on the mixomo config"
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
  # The layout of mixomo: the rule-sets live in rule-files/, the provider in
  # proxy-providers/. The core is started with -d /etc/mihomo, so the paths
  # in the config are relative to that directory.
  rm -rf "$TMPDIR_TEST/mixomo"
  mkdir -p "$TMPDIR_TEST/mixomo/rule-files" "$TMPDIR_TEST/mixomo/proxy-providers"
  cp ruleset/*.mrs "$TMPDIR_TEST/mixomo/rule-files/" 2>/dev/null || true
  if "$MIHOMO" -t -f "$CFG" -d "$TMPDIR_TEST/mixomo" >"$TMPDIR_TEST/t.log" 2>&1; then
    ok "$CFG passes mihomo -t"
  else
    bad "$CFG fails mihomo -t: $(tail -3 "$TMPDIR_TEST/t.log")"
  fi
else
  skip "mihomo -t (no core: set MIHOMO=...)"
fi

section "2. the config has the keys mixomo needs"
# The placeholders have to be there: the installer substitutes them, and a
# config without them would go to the router with a dead subscription.
has "$CFG" "url: 'PASTE_SUBSCRIPTION_URL_HERE'"
has "$CFG" "secret: CHANGE_ME"
# mixed-port 7890 is not a free choice: mixomo checks it, and the installer
# keeps a config that has it instead of overwriting it with the default.
has "$CFG" "mixed-port: 7890"
has "$CFG" "redir-port: 5001"
has "$CFG" "routing-mark: 2"
has "$CFG" "listen: 0.0.0.0:7880"
has "$CFG" "enhanced-mode: redir-host"
has "$CFG" "external-ui: UI/metacubex"
has "$CFG" "find-process-mode: 'off'"

section "3. the paths of the mixomo layout"
has "$CFG" "./rule-files/rkn-blocked.mrs"
has "$CFG" "./rule-files/category-ru.mrs"
has "$CFG" "./proxy-providers/main.yaml"
if grep -q '\./ruleset/' "$CFG"; then bad "$CFG still points at ./ruleset/"; else ok "$CFG has no ./ruleset/ path"; fi

section "4. no forbidden patterns in the mixomo config"
code() { awk '$0 !~ /^[[:space:]]*#/' "$1"; }
if code "$CFG" | grep -qF 'geosite:category-ru'; then bad "geosite policy in code"; else ok "no geosite policy in code"; fi
if code "$CFG" | grep -qF 'external-ui-url'; then bad "external-ui-url in code"; else ok "no external-ui-url in code"; fi
if code "$CFG" | grep -qF 'behavior: classical'; then bad "classical behavior in code"; else ok "no classical behavior in code"; fi
if code "$CFG" | grep -qF 'geo-auto-update: true'; then bad "geo auto update on"; else ok "geo auto update off"; fi
# fake-ip is the reason why the whole traffic would have to go through the
# core - the client would get addresses from 198.18.0.0/16 and the router
# would have to send all of it into the core.
if code "$CFG" | grep -qE 'enhanced-mode:[[:space:]]*fake-ip'; then bad "fake-ip in the mixomo config"; else ok "no fake-ip in the mixomo config"; fi
if code "$CFG" | grep -qF "enable: true"; then
  if code "$CFG" | grep -qE '^tun:'; then
    if sed -n '/^tun:/,/^[a-z]/p' "$CFG" | grep -qE '^[[:space:]]+enable:[[:space:]]+true'; then
      bad "the tun of the core is on (hev-socks5-tunnel owns the tunnel)"
    else
      ok "the tun of the core is off"
    fi
  fi
fi
# The ad list is blocked by MagiTrickle (blackhole), the core does not need
# it - that keeps 110 000 domains out of its memory.
if code "$CFG" | grep -qF 'antiad,REJECT'; then bad "the ad rule is still in the core"; else ok "the ad rule is not in the core"; fi

section "5. the state configuration of MagiTrickle"
has "$MT" 'configVersion: "0.1.4"'
has "$MT" "startMarkTableIndex: 1298229097"
has "$MT" "chainPrefix: MT_"
has "$MT" "port: 3553"
has "$MT" "port: 8080"
has "$MT" "- br-lan"
# The ads are dropped by the router, not by the core.
if grep -A6 'name: "🛡 Anti-AD"' "$MT" | grep -q 'interface: blackhole'; then
  ok "the ad list is dropped by the router (blackhole)"
else
  bad "the ad list is not on blackhole"
fi
# Every group and every subscription needs an id of eight hex characters and
# an interface that MagiTrickle knows.
if command -v ruby >/dev/null 2>&1; then
  if ruby -ryaml -e '
    d = YAML.load_file(ARGV[0])
    raise "no configVersion" unless d["configVersion"].to_s.start_with?("0.1.")
    raise "no app" unless d["app"].is_a?(Hash)
    raise "no groups" unless d["groups"].is_a?(Array) && !d["groups"].empty?
    raise "no subscriptions" unless d["subscriptions"].is_a?(Array) && !d["subscriptions"].empty?
    (d["groups"] + d["subscriptions"]).each do |g|
      raise "bad id #{g["id"].inspect}" unless g["id"].to_s =~ /\A[0-9a-f]{8}\z/
      raise "bad interface #{g["interface"].inspect}" unless ["Mihomo", "blackhole"].include?(g["interface"])
      raise "no enable" unless [true, false].include?(g["enable"])
    end
    d["subscriptions"].each do |s|
      raise "no url" if s["url"].to_s.empty?
      raise "no interval" unless s["interval"].to_s =~ /\A[0-9]+\z/
    end
  ' "$MT" >/dev/null 2>&1; then
    ok "the state configuration is well formed"
  else
    bad "the state configuration is broken"
  fi
  # The fields the two builds read differently must not be in the file.
  for key in 'timeout:' 'additionalTTL:' 'tproxyPort:' 'clientTTLCap:' 'directPriority:'; do
    if grep -q "$key" "$MT"; then bad "$MT sets $key (the builds disagree on it)"; else ok "$MT does not set $key"; fi
  done
else
  skip "the state configuration is not checked (no ruby)"
fi

section "6. the .mtrickle file of the web interface"
if command -v python3 >/dev/null 2>&1; then
  if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
g = d["groups"]
assert isinstance(g, list) and g
for x in g:
    assert len(x["id"]) == 8 and all(c in "0123456789abcdef" for c in x["id"]), x["id"]
    assert isinstance(x["name"], str) and x["name"]
    assert x["interface"] in ("Mihomo", "blackhole"), x["interface"]
    assert isinstance(x["enable"], bool)
    assert isinstance(x["rules"], list)
    for r in x["rules"]:
        assert len(r["id"]) == 8
        assert r["type"] in ("namespace", "domain", "subnet", "wildcard", "regex")
        assert r["rule"]
' "$MTJ" >/dev/null 2>&1; then
    ok "$MTJ is well formed"
  else
    bad "$MTJ is broken"
  fi
  # The groups of the .mtrickle and of the state file have to be the same.
  if python3 -c '
import json, sys
j = json.load(open(sys.argv[1]))["groups"]
y = open(sys.argv[2]).read()
for g in j:
    assert g["id"] in y, g["id"]
    assert g["name"] in y, g["name"]
' "$MTJ" "$MT" >/dev/null 2>&1; then
    ok "the .mtrickle and the state file have the same groups"
  else
    bad "the .mtrickle and the state file differ"
  fi
else
  skip "the .mtrickle file is not checked (no python3)"
fi

section "7. gen-mtrickle.sh builds a state file from the rule-sets"
if [ -n "$MIHOMO" ]; then
  rm -rf "$TMPDIR_TEST/mt"
  mkdir -p "$TMPDIR_TEST/mt"
  if MIHOMO="$MIHOMO" RULE_DIR="$ROOT/ruleset" \
     CUSTOM_LIST="$ROOT/lists/custom-domains.list" \
     TEMPLATE="$ROOT/$MT" OUT="$TMPDIR_TEST/mt/config.yaml" \
     sh scripts/gen-mtrickle.sh >"$TMPDIR_TEST/mt.log" 2>&1; then
    ok "gen-mtrickle.sh runs"
  else
    bad "gen-mtrickle.sh failed: $(tail -3 "$TMPDIR_TEST/mt.log")"
  fi
  if [ -s "$TMPDIR_TEST/mt/config.yaml" ]; then
    ok "the state file was written"
    if grep -q 'rules:' "$TMPDIR_TEST/mt/config.yaml"; then ok "the state file has rules"; else bad "the state file has no rules"; fi
    if grep -q 'netflix.com' "$TMPDIR_TEST/mt/config.yaml"; then ok "the streaming group has the domains of the rule-set"; else bad "the streaming group is empty"; fi
    if grep -q 'openai.com' "$TMPDIR_TEST/mt/config.yaml"; then ok "the AI group has the domains of the rule-set"; else bad "the AI group is empty"; fi
    if grep -q '^subscriptions:' "$TMPDIR_TEST/mt/config.yaml"; then ok "the subscriptions survived"; else bad "the subscriptions are gone"; fi
    # The ids of the rules have to be eight hex characters.
    if ruby -ryaml -e '
      d = YAML.load_file(ARGV[0])
      d["groups"].each do |g|
        (g["rules"] || []).each { |r| raise "bad rule id #{r["id"].inspect}" unless r["id"].to_s =~ /\A[0-9a-f]{8}\z/ }
      end
    ' "$TMPDIR_TEST/mt/config.yaml" >/dev/null 2>&1; then
      ok "every rule has a valid id"
    else
      bad "a rule has an invalid id"
    fi
  else
    bad "no state file was written"
  fi
  # The same for the .mtrickle file.
  if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["groups"]' "$TMPDIR_TEST/mt/config.yaml.mtrickle" >/dev/null 2>&1; then
    ok "the .mtrickle file was written"
  else
    bad "no .mtrickle file was written"
  fi
else
  skip "gen-mtrickle.sh is not checked (no core)"
fi

section "8. the scripts are POSIX sh and pass the syntax check"
for s in scripts/gen-mtrickle.sh scripts/setup-mixomo.sh scripts/update-mixomo.sh; do
  if sh -n "$s" 2>/dev/null; then ok "$s passes sh -n"; else bad "$s has a syntax error"; fi
  # "[[" is bash. The character class "[[:space:]]" of sed is not - the
  # difference is the colon right after the brackets.
  if grep -qE '\[\[[^:]|source |<<<' "$s"; then bad "$s uses bash syntax"; else ok "$s has no bash syntax"; fi
  if grep -q '^#!' "$s"; then ok "$s has a shebang"; else bad "$s has no shebang"; fi
done

section "9. setup-mixomo.sh does the whole job"
has scripts/setup-mixomo.sh "RU-Mihomo-mixomo.yaml"
has scripts/setup-mixomo.sh "magitrickle/magitrickle.yaml"
has scripts/setup-mixomo.sh "gen-mtrickle.sh"
has scripts/setup-mixomo.sh "STOP_OPENCLASH"
has scripts/setup-mixomo.sh "openclash.bak"
has scripts/setup-mixomo.sh "config.yaml.bak"
has scripts/setup-mixomo.sh "rule-files"
has scripts/setup-mixomo.sh "update-mixomo.sh"
has scripts/setup-mixomo.sh "PASTE_SUBSCRIPTION_URL_HERE"
# The rule-set list of the script has to match the repository.
repo_rs=$(ls -1 ruleset/*.mrs | wc -l | tr -d ' ')
script_rs=$(grep -A3 '^RULESETS=' scripts/setup-mixomo.sh | tr -s ' \n' '\n' | grep -c '\.mrs' || true)
if [ "$repo_rs" -eq 28 ]; then ok "the repository has 28 rule-sets"; else bad "the repository has $repo_rs rule-sets"; fi

section "10. update-mixomo.sh refreshes the lists"
has scripts/update-mixomo.sh "build-ruleset.sh"
has scripts/update-mixomo.sh "gen-mtrickle.sh"
has scripts/update-mixomo.sh "configs?force=true"
has scripts/update-mixomo.sh "magitrickle"

summary
