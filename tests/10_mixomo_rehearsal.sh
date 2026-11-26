#!/usr/bin/env bash
# The rehearsal of the mixomo scheme: setup-mixomo.sh really installs the
# scheme, into a directory of our own, from a local copy of the repository.
set -u
. "$(dirname "$0")/lib.sh"
cd "$ROOT"

section "1. what the rehearsal needs"
if [ "$(id -u)" != "0" ]; then
  skip "the rehearsal needs root (it writes into /etc/init.d for the fake services)"
  summary
  exit 0
fi
ok "running as root"

MIHOMO="${MIHOMO:-}"
if [ -z "$MIHOMO" ] || [ ! -x "$MIHOMO" ]; then
  if command -v mihomo >/dev/null 2>&1; then
    MIHOMO=$(command -v mihomo)
  elif [ -x "$ROOT/mihomo" ]; then
    MIHOMO="$ROOT/mihomo"
  else
    MIHOMO=""
  fi
fi
if [ -z "$MIHOMO" ]; then
  skip "the rehearsal needs a core (set MIHOMO=...)"
  summary
  exit 0
fi
ok "core: $MIHOMO"

# The scheme expects the services of mixomo. They are replaced by fakes that
# only answer "running" - the rehearsal is about the files, not about the
# tunnel.
FAKE=/tmp/mihomo-mixomo-fakes.$$
mkdir -p "$FAKE"
for svc in magitrickle hev-socks5-tunnel mihomo mixomo-routing; do
  cat >"/etc/init.d/$svc" <<EOF
#!/bin/sh
case "\$1" in
  running|status) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "/etc/init.d/$svc"
done
cleanup() { rm -f "/etc/init.d/magitrickle" "/etc/init.d/hev-socks5-tunnel" "/etc/init.d/mihomo" "/etc/init.d/mixomo-routing" "/etc/init.d/mixomo-bypass"; rm -rf "$FAKE"; }
trap 'cleanup; rm -rf "$TMPDIR_TEST"' EXIT

# The core has to be found by name.
mkdir -p "$FAKE/bin"
ln -sf "$MIHOMO" "$FAKE/bin/mihomo"
export PATH="$FAKE/bin:$PATH"

section "2. a local copy of the repository serves the files"
PORT=18099
while nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; do PORT=$((PORT + 1)); done
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT" >"$TMPDIR_TEST/http.log" 2>&1 &
HTTP_PID=$!
sleep 1
if kill -0 "$HTTP_PID" 2>/dev/null; then ok "the local server is up on $PORT"; else bad "the local server did not start"; summary; exit 1; fi

section "3. setup-mixomo.sh installs the scheme"
MIXDIR="$TMPDIR_TEST/mihomo"
MAGDIR="$TMPDIR_TEST/magitrickle"
set +e
SUB_URL='https://provider/subscribe?token=a&b=c' \
DASHBOARD_PASSWORD='p@ss|w:rd' \
BASE_URL="http://127.0.0.1:$PORT" \
MIHOMO_DIR="$MIXDIR" \
MAGITRICKLE_DIR="$MAGDIR" \
ENABLE_CRON=0 \
CHECKS=0 \
  sh scripts/setup-mixomo.sh >"$TMPDIR_TEST/setup.log" 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then ok "setup-mixomo.sh finished without an error"; else bad "setup-mixomo.sh failed: $(tail -3 "$TMPDIR_TEST/setup.log")"; fi

section "4. what was installed"
if [ -f "$MIXDIR/config.yaml" ]; then ok "the config is in place"; else bad "no config"; fi
if [ -f "$MIXDIR/magitrickle.yaml" ]; then ok "the MagiTrickle template is in place"; else bad "no MagiTrickle template"; fi
n=$(ls -1 "$MIXDIR/rule-files"/*.mrs 2>/dev/null | wc -l | tr -d ' ')
if [ "$n" -eq 28 ]; then ok "28 rule-sets are in place"; else bad "$n rule-sets are in place"; fi
for s in build-ruleset.sh gen-mtrickle.sh update-mixomo.sh apply-rulesets.sh check-groups.sh; do
  if [ -x "$MIXDIR/scripts/$s" ]; then ok "$s is installed and executable"; else bad "$s is missing or not executable"; fi
done
if [ -f "$MIXDIR/lists/custom-domains.list" ]; then ok "the custom list is in place"; else bad "no custom list"; fi
if [ -x "$MIXDIR/scripts/bypass-ports.sh" ]; then ok "bypass-ports.sh is installed and executable"; else bad "bypass-ports.sh is missing"; fi
if [ -f "$MIXDIR/bypass-ports.txt" ]; then ok "the list of the ports is in place"; else bad "no list of the ports"; fi
if [ -x /etc/init.d/mixomo-bypass ]; then ok "the init script of the bypass is installed"; else bad "the init script of the bypass is missing"; fi

section "5. the placeholders were substituted"
if grep -qF 'https://provider/subscribe?token=a&b=c' "$MIXDIR/config.yaml"; then ok "the subscription URL is in the config"; else bad "the subscription URL is missing"; fi
if grep -qF "secret: p@ss|w:rd" "$MIXDIR/config.yaml"; then ok "the password is in the config"; else bad "the password is missing"; fi
if grep -q 'PASTE_SUBSCRIPTION_URL_HERE\|CHANGE_ME' "$MIXDIR/config.yaml"; then bad "a placeholder is left"; else ok "no placeholder is left"; fi

section "6. the state of MagiTrickle was built"
if [ -s "$MAGDIR/state/config.yaml" ]; then ok "the state file is in place"; else bad "no state file"; fi
if grep -q 'netflix.com' "$MAGDIR/state/config.yaml" 2>/dev/null; then ok "the state file has the domains of the rule-sets"; else bad "the state file has no rules"; fi
if grep -q '^subscriptions:' "$MAGDIR/state/config.yaml" 2>/dev/null; then ok "the subscriptions survived"; else bad "the subscriptions are gone"; fi
if [ -s "$MAGDIR/state/config.yaml.mtrickle" ]; then ok "the .mtrickle file is in place"; else bad "no .mtrickle file"; fi

section "6a. the ports of the bypass"
# The ports of the user go into the file of the router and stay there.
printf '25565\n' >"$MIXDIR/bypass-ports.txt"
set +e
SUB_URL='https://provider/subscribe?token=a&b=c' \
DASHBOARD_PASSWORD='p@ss|w:rd' \
BASE_URL="http://127.0.0.1:$PORT" \
MIHOMO_DIR="$MIXDIR" \
MAGITRICKLE_DIR="$MAGDIR" \
ENABLE_CRON=0 \
CHECKS=0 \
  sh scripts/setup-mixomo.sh >>"$TMPDIR_TEST/setup.log" 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then ok "the run with a list of the ports finished"; else bad "the run with a list of the ports failed"; fi
if grep -q '25565' "$MIXDIR/bypass-ports.txt"; then ok "the list of the ports was kept"; else bad "the list of the ports was overwritten"; fi

section "7. the install is repeatable and keeps the custom list"
echo "my-site.ru" >>"$MIXDIR/lists/custom-domains.list"
set +e
SUB_URL='https://provider/subscribe?token=a&b=c' \
DASHBOARD_PASSWORD='p@ss|w:rd' \
BASE_URL="http://127.0.0.1:$PORT" \
MIHOMO_DIR="$MIXDIR" \
MAGITRICKLE_DIR="$MAGDIR" \
ENABLE_CRON=0 \
CHECKS=0 \
  sh scripts/setup-mixomo.sh >>"$TMPDIR_TEST/setup.log" 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then ok "the second run finished without an error"; else bad "the second run failed: $(tail -3 "$TMPDIR_TEST/setup.log")"; fi
if grep -q 'my-site.ru' "$MIXDIR/lists/custom-domains.list"; then ok "the custom list was kept"; else bad "the custom list was overwritten"; fi
if grep -q 'my-site.ru' "$MAGDIR/state/config.yaml" 2>/dev/null; then ok "the own domain is in the state file"; else bad "the own domain is not in the state file"; fi

section "8. the ports that bypass the core"
# A stub for iptables: it records the calls and reports an empty
# PREROUTING, so the script has to hook its chain in itself.
cat >"$FAKE/bin/iptables" <<'STUB'
#!/bin/sh
echo "$@" >> "$IPT_LOG"
case "$*" in
  *-L*PREROUTING*) exit 0 ;;
esac
exit 0
STUB
chmod +x "$FAKE/bin/iptables"
export IPT_LOG="$TMPDIR_TEST/iptables.log"
: >"$IPT_LOG"

PORTS="$TMPDIR_TEST/bypass-ports.txt"
printf '# the Rust servers\n25565\n\n28015\n' >"$PORTS"

if PORTS_FILE="$PORTS" IPT="$FAKE/bin/iptables" sh scripts/bypass-ports.sh install >"$TMPDIR_TEST/bypass.log" 2>&1; then
  ok "bypass-ports.sh installs"
else
  bad "bypass-ports.sh failed: $(tail -3 "$TMPDIR_TEST/bypass.log")"
fi
for proto in tcp udp; do
  if grep -q -- "-t mangle -A MIXOMO_BYPASS ! -i lo -p $proto --dport 25565.*-j ACCEPT" "$IPT_LOG"; then
    ok "the mangle rule for $proto 25565 is there"
  else
    bad "the mangle rule for $proto 25565 is missing"
  fi
  if grep -q -- "-t nat -A MIXOMO_BYPASS ! -i lo -p $proto --dport 28015.*-j ACCEPT" "$IPT_LOG"; then
    ok "the nat rule for $proto 28015 is there"
  else
    bad "the nat rule for $proto 28015 is missing"
  fi
done
if grep -q -- "-t mangle -I PREROUTING 1 -j MIXOMO_BYPASS" "$IPT_LOG"; then
  ok "the chain is hooked in first in mangle PREROUTING"
else
  bad "the chain is not hooked in first in mangle PREROUTING"
fi
if grep -q -- "-t nat -I PREROUTING 1 -j MIXOMO_BYPASS" "$IPT_LOG"; then
  ok "the chain is hooked in first in nat PREROUTING"
else
  bad "the chain is not hooked in first in nat PREROUTING"
fi
# The comments and the empty lines of the file are not ports.
if grep -q -- "--dport Rust" "$IPT_LOG"; then bad "a comment became a port"; else ok "the comments are not ports"; fi

: >"$IPT_LOG"
if PORTS_FILE="$PORTS" IPT="$FAKE/bin/iptables" sh scripts/bypass-ports.sh uninstall >/dev/null 2>&1; then
  ok "bypass-ports.sh uninstalls"
else
  bad "bypass-ports.sh uninstall failed"
fi
if grep -q -- "-X MIXOMO_BYPASS" "$IPT_LOG"; then ok "the chain is removed"; else bad "the chain is not removed"; fi

# An empty list means: nothing to bypass, and the rules are taken away.
: >"$IPT_LOG"
printf '# nothing\n' >"$PORTS"
if PORTS_FILE="$PORTS" IPT="$FAKE/bin/iptables" sh scripts/bypass-ports.sh install >"$TMPDIR_TEST/bypass2.log" 2>&1; then
  ok "an empty list is handled"
else
  bad "an empty list failed"
fi
if grep -q 'nothing to bypass' "$TMPDIR_TEST/bypass2.log"; then ok "the empty list is reported"; else bad "the empty list is not reported"; fi

section "9. the password does not leak into the log"
if grep -qF 'p@ss|w:rd' "$TMPDIR_TEST/setup.log"; then bad "the password is in the log"; else ok "the password is not in the log"; fi

kill "$HTTP_PID" 2>/dev/null || true

summary
