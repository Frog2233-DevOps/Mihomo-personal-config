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
cleanup() { rm -f "/etc/init.d/magitrickle" "/etc/init.d/hev-socks5-tunnel" "/etc/init.d/mihomo" "/etc/init.d/mixomo-routing"; rm -rf "$FAKE"; }
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

section "5. the placeholders were substituted"
if grep -qF 'https://provider/subscribe?token=a&b=c' "$MIXDIR/config.yaml"; then ok "the subscription URL is in the config"; else bad "the subscription URL is missing"; fi
if grep -qF "secret: p@ss|w:rd" "$MIXDIR/config.yaml"; then ok "the password is in the config"; else bad "the password is missing"; fi
if grep -q 'PASTE_SUBSCRIPTION_URL_HERE\|CHANGE_ME' "$MIXDIR/config.yaml"; then bad "a placeholder is left"; else ok "no placeholder is left"; fi

section "6. the state of MagiTrickle was built"
if [ -s "$MAGDIR/state/config.yaml" ]; then ok "the state file is in place"; else bad "no state file"; fi
if grep -q 'netflix.com' "$MAGDIR/state/config.yaml" 2>/dev/null; then ok "the state file has the domains of the rule-sets"; else bad "the state file has no rules"; fi
if grep -q '^subscriptions:' "$MAGDIR/state/config.yaml" 2>/dev/null; then ok "the subscriptions survived"; else bad "the subscriptions are gone"; fi
if [ -s "$MAGDIR/state/config.yaml.mtrickle" ]; then ok "the .mtrickle file is in place"; else bad "no .mtrickle file"; fi

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

section "8. the password does not leak into the log"
if grep -qF 'p@ss|w:rd' "$TMPDIR_TEST/setup.log"; then bad "the password is in the log"; else ok "the password is not in the log"; fi

kill "$HTTP_PID" 2>/dev/null || true

summary
