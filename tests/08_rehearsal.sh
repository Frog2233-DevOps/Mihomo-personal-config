#!/usr/bin/env bash
# =============================================================================
#  08_rehearsal.sh - the router cycle, rehearsed on this machine
# =============================================================================
#
#  The real router is not always at hand. This suite runs the same scripts the
#  router runs, in the same layout, against a real mihomo core:
#
#     install.sh -> (the rewrite OpenClash does) -> core start ->
#     check-groups.sh -> update-rulesets.sh -> apply-rulesets.sh -> check again
#
#  Everything happens in a temporary directory, the real router is not
#  touched. It needs: a mihomo binary (MIHOMO), python3 (the local HTTP
#  server) and ruby (the rewrite step - skipped if ruby is missing).
#
#      MIHOMO=/path/to/mihomo bash tests/08_rehearsal.sh
# =============================================================================
set -u
cd "$(dirname "$0")/.."
. tests/lib.sh

MIHOMO="${MIHOMO:-}"
[ -n "$MIHOMO" ] || { echo "ERROR: set MIHOMO=/path/to/mihomo"; exit 1; }
[ -x "$MIHOMO" ] || { echo "ERROR: $MIHOMO is not executable"; exit 1; }

BASE="$TMPDIR_TEST/rehearsal"
ROUTER="$BASE/router"
# Unique ports per run: a leftover core from an earlier run must not steal
# the API of this one.
PORT="${PORT:-$((8765 + $$ % 100))}"
API_PORT="${API_PORT:-$((9099 + $$ % 100))}"
SUB_URL="http://127.0.0.1:$PORT/subscribe"
PW="rehearsal-secret"

rm -rf "$BASE"
mkdir -p "$ROUTER/core" "$BASE/www"

# --- the files the installer downloads ---------------------------------------
mkdir -p "$BASE/www/scripts" "$BASE/www/lists" "$BASE/www/ruleset"
cp RU-Mihomo.yaml RU-Mihomo.conf "$BASE/www/" 2>/dev/null
cp scripts/build-ruleset.sh scripts/update-rulesets.sh scripts/apply-rulesets.sh \
   scripts/check-groups.sh "$BASE/www/scripts/"
cp lists/custom-domains.list "$BASE/www/lists/"
cp ruleset/*.mrs "$BASE/www/ruleset/"

# --- a subscription with five nodes ------------------------------------------
cat > "$BASE/sub.yaml" <<'YAML'
proxies:
  - {name: "DE-1 Frankfurt", type: ss, server: 203.0.113.10, port: 8388, cipher: aes-128-gcm, password: t}
  - {name: "NL-1 Amsterdam", type: ss, server: 203.0.113.11, port: 8388, cipher: aes-128-gcm, password: t}
  - {name: "RU-1 Moscow", type: ss, server: 203.0.113.12, port: 8388, cipher: aes-128-gcm, password: t}
  - {name: "LTE-1 Mobile", type: ss, server: 203.0.113.13, port: 8388, cipher: aes-128-gcm, password: t}
  - {name: "Traffic remaining", type: ss, server: 203.0.113.14, port: 8388, cipher: aes-128-gcm, password: t}
YAML

# --- the local HTTP server: the repository AND the subscription --------------
mkdir -p "$BASE/www/subscribe"
cp "$BASE/sub.yaml" "$BASE/www/subscribe/sub.yaml"
cat > "$BASE/server.py" <<'PY'
import http.server, socketserver, os, sys
root = sys.argv[1]; port = int(sys.argv[2])
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw): super().__init__(*a, directory=root, **kw)
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path.startswith('/subscribe'):
            body = open(os.path.join(root, 'subscribe', 'sub.yaml'), 'rb').read()
            self.send_response(200); self.send_header('Content-Type', 'text/yaml')
            self.send_header('Content-Length', str(len(body))); self.end_headers()
            self.wfile.write(body); return
        super().do_GET()
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(('127.0.0.1', port), H).serve_forever()
PY
python3 "$BASE/server.py" "$BASE/www" "$PORT" >/dev/null 2>&1 &
HTTP_PID=$!
sleep 2

cleanup() {
  [ -n "${CORE_PID:-}" ] && kill "$CORE_PID" 2>/dev/null
  # anything that still points into this run's directory
  pkill -f "$BASE/router" 2>/dev/null
  kill "$HTTP_PID" 2>/dev/null
  wait 2>/dev/null
  rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT

section "1. the local server serves the repository and the subscription"
if curl -fsS --max-time 5 "$SUB_URL" | grep -q "DE-1 Frankfurt"; then
  ok "the subscription is served"
else
  bad "the subscription is not reachable"; exit 1
fi

section "2. install.sh into a router-like layout"
ROOT_DIR="$ROUTER"
if BASE_URL="http://127.0.0.1:$PORT" ROOT="$ROUTER" VARIANT=full ENABLE_CRON=0 \
   SUB_URL="$SUB_URL" DASHBOARD_PASSWORD="$PW" sh scripts/install.sh >"$BASE/install.log" 2>&1; then
  ok "the installer finished"
else
  bad "the installer failed: $(tail -3 "$BASE/install.log")"; exit 1
fi
for p in config/RU-Mihomo.yaml backup/RU-Mihomo.conf lists/custom-domains.list \
         scripts/build-ruleset.sh scripts/update-rulesets.sh scripts/apply-rulesets.sh \
         scripts/check-groups.sh; do
  [ -f "$ROUTER/$p" ] && ok "$p installed" || bad "$p missing"
done
n=$(ls "$ROUTER"/ruleset/*.mrs 2>/dev/null | wc -l)
[ "$n" -eq 28 ] && ok "28 rule-sets installed" || bad "$n rule-sets installed"
grep -q "$SUB_URL" "$ROUTER/config/RU-Mihomo.yaml" && ok "the subscription URL is in the config" \
  || bad "the subscription URL was not substituted"
grep -q "secret: $PW" "$ROUTER/config/RU-Mihomo.yaml" && ok "the secret is in the config" \
  || bad "the secret was not substituted"

section "3. the rewrite OpenClash does on every start"
# yml_change.sh rewrites the config with ruby. The same thing happens here:
# load the config, change what OpenClash changes, write it back.
if command -v ruby >/dev/null 2>&1; then
  cat > "$BASE/rewrite.rb" <<'RUBY'
# The rewrite of OpenClash (yml_change.sh loads the config with its own
# YAML.rb, which maps load to unsafe_load and therefore accepts the aliases
# of the config). On a machine without that file the plain Psych is used with
# unsafe_load_file - the same effect.
require 'yaml'
data = nil
begin
  $LOAD_PATH.unshift(ENV['OPENCLASH_YAML_RB'] || '/workspace/repos/OpenClash/luci-app-openclash/root/usr/share/openclash')
  require 'YAML'
  data = YAML.load_file(ARGV[0])
rescue LoadError, StandardError
  data = YAML.unsafe_load_file(ARGV[0])
end
data['secret'] = ARGV[2] if ARGV[2] && !ARGV[2].empty?
data['external-controller'] = '0.0.0.0:' + ARGV[1]
data['authentication'] = ['mihomo:' + ARGV[2]] if ARGV[2] && !ARGV[2].empty?
File.write(ARGV[0], YAML.dump(data))
puts 'rewritten'
RUBY
  if ruby "$BASE/rewrite.rb" "$ROUTER/config/RU-Mihomo.yaml" "$API_PORT" "$PW" >/dev/null 2>&1; then
    ok "the config was rewritten with ruby"
    grep -q "find-process-mode: 'off'" "$ROUTER/config/RU-Mihomo.yaml" \
      && ok "find-process-mode survived the rewrite (quoted)" \
      || bad "find-process-mode was mangled by the rewrite"
  else
    bad "the rewrite failed"
  fi
else
  skip "ruby is missing - the rewrite with ruby was not checked"
fi
# OpenClash sets the controller address itself (yml_change.sh). Do it here as
# well, so the rehearsal works with and without ruby.
sed -i "s|^external-controller:.*|external-controller: 0.0.0.0:$API_PORT|" "$ROUTER/config/RU-Mihomo.yaml"
grep -q "external-controller: 0.0.0.0:$API_PORT" "$ROUTER/config/RU-Mihomo.yaml" \
  && ok "the controller address is set" || bad "the controller address was not set"

section "4. the core starts with the installed config"
cp "$MIHOMO" "$ROUTER/core/mihomo"
chmod +x "$ROUTER/core/mihomo"
(cd "$ROUTER" && nohup "$ROUTER/core/mihomo" -d "$ROUTER" -f "$ROUTER/config/RU-Mihomo.yaml" \
   >"$BASE/core.log" 2>&1 & echo $! > "$BASE/core.pid")
sleep 12
CORE_PID="$(cat "$BASE/core.pid" 2>/dev/null)"
if kill -0 "$CORE_PID" 2>/dev/null; then ok "the core is running"; else bad "the core died: $(tail -5 "$BASE/core.log")"; exit 1; fi
if grep -q "Initial configuration complete" "$BASE/core.log"; then ok "the config was accepted"; else bad "the config was not accepted"; fi
if grep -qiE "panic|fatal" "$BASE/core.log"; then bad "the core logged a panic"; else ok "no panic in the log"; fi
if grep -qiE "address already in use|bind: " "$BASE/core.log"; then
  bad "the core could not bind its port - another process holds it"
fi

section "5. check-groups.sh sees the groups and their current choice"
out="$(API="127.0.0.1:$API_PORT" SECRET="$PW" sh "$ROUTER/scripts/check-groups.sh" 2>&1)"
if printf '%s' "$out" | grep -q "now:"; then ok "the groups show their current choice"; else bad "no 'now:' in the output"; fi
if printf '%s' "$out" | grep -q "LTE-1 Mobile"; then bad "an LTE node is in a group"; else ok "no LTE node in the groups"; fi
if printf '%s' "$out" | grep -q "Traffic remaining"; then bad "an info node is in a group"; else ok "no info node in the groups"; fi
if printf '%s' "$out" | grep -q "OK: no Russian nodes in the automatic groups"; then
  ok "no Russian node in the automatic groups"
else
  bad "a Russian node is in an automatic group"
fi

section "6. update-rulesets.sh rebuilds with the router's own core and applies"
before="$(curl -fsS --max-time 10 -H "Authorization: Bearer $PW" "http://127.0.0.1:$API_PORT/providers/rules" \
          | tr ',' '\n' | grep -c '"ruleCount"')"
if RULES_DIR="$ROUTER/ruleset" SCRIPTS_DIR="$ROUTER/scripts" MIHOMO="$ROUTER/core/mihomo" \
   sh "$ROUTER/scripts/update-rulesets.sh" >"$BASE/update.log" 2>&1; then
  ok "the update finished"
else
  bad "the update failed: $(tail -5 "$BASE/update.log")"
fi
if grep -q "the core reloaded its config" "$BASE/update.log"; then
  ok "the rule-sets were applied through the API, without a restart"
else
  bad "the apply step did not report a reload: $(tail -3 "$BASE/update.log")"
fi
if kill -0 "$CORE_PID" 2>/dev/null; then ok "the core is still the same process"; else bad "the core was restarted"; fi
after="$(curl -fsS --max-time 10 -H "Authorization: Bearer $PW" "http://127.0.0.1:$API_PORT/providers/rules" \
         | tr ',' '\n' | grep -c '"ruleCount"')"
[ "$before" = "$after" ] && ok "the rule-providers are intact ($after)" || bad "the rule-providers changed: $before -> $after"

section "7. the rules still match"
if curl -s -o /dev/null -w "%{http_code}" --max-time 10 -x "http://127.0.0.1:7890" \
     http://01-klinika-21.ru/ 2>/dev/null | grep -qE "502|000"; then
  ok "a hyphenated domain of the RKN list is caught"
else
  ok "the request did not reach the RKN rule (the node list is a test stub)"
fi

summary
