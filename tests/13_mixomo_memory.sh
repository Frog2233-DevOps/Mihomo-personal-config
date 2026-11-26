#!/usr/bin/env bash
# The memory of the scheme: the daemon of MagiTrickle keeps every domain of
# every list in its RAM, so the lists that do not fit have to be switched off
# before the state file is written - otherwise the oom-killer of the kernel
# takes the daemon and nothing is updated any more.
set -u
. "$(dirname "$0")/lib.sh"
cd "$ROOT"

RAM=scripts/mixomo-ram.sh
LIMIT=scripts/mixomo-memlimit.sh
GEN=scripts/gen-mtrickle.sh

section "1. the files of the fix"

for f in "$RAM" "$LIMIT"; do
  if [ -f "$f" ]; then ok "$f exists"; else bad "$f is missing"; fi
  if sh -n "$f" 2>/dev/null; then ok "$f passes sh -n"; else bad "$f has a syntax error"; fi
  if grep -qE '\[\[[^:]|source |<<<' "$f"; then bad "$f uses bash syntax"; else ok "$f has no bash syntax"; fi
  if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -s sh "$f" >/dev/null 2>&1; then ok "$f passes shellcheck"; else bad "$f has a shellcheck warning"; fi
  else
    skip "$f is not checked by shellcheck (no shellcheck)"
  fi
done

section "2. the report of the memory"

out=$(sh "$RAM" 2>&1)
if printf '%s' "$out" | grep -q 'the memory of the router'; then ok "the report has the memory of the router"; else bad "the report is empty: $out"; fi
if printf '%s' "$out" | grep -q 'MemTotal'; then ok "the report shows MemTotal"; else bad "the report has no MemTotal"; fi
if printf '%s' "$out" | grep -q 'mihomo'; then ok "the report has the processes of the scheme"; else bad "the report has no processes"; fi
if printf '%s' "$out" | grep -q 'the swap'; then ok "the report has the swap"; else bad "the report has no swap"; fi
# The report must not break when there is no ipset and no logread.
if sh "$RAM" --log >/dev/null 2>&1; then ok "the report works with --log"; else bad "the report fails with --log"; fi

section "3. the soft memory limit"

FAKE="$TMPDIR_TEST/fake"
mkdir -p "$FAKE/init.d"
cat >"$FAKE/init.d/magitrickle" <<'EOF'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=99
procd_open_instance
procd_set_param command /usr/bin/magitrickled
procd_set_param respawn
procd_close_instance
EOF
cp "$FAKE/init.d/magitrickle" "$FAKE/init.d/mihomo"

# The script patches the init scripts of the router, so the paths are given
# through the environment of the test.
sed "s#/etc/init.d/mihomo#$FAKE/init.d/mihomo#; s#/etc/init.d/magitrickle#$FAKE/init.d/magitrickle#" \
  "$LIMIT" >"$FAKE/limit.sh"

out=$(sh "$FAKE/limit.sh" 2>&1)
if grep -q 'procd_set_param env GOMEMLIMIT=96MiB' "$FAKE/init.d/mihomo"; then
  ok "the core got the limit"
else
  bad "the core did not get the limit: $(cat "$FAKE/init.d/mihomo")"
fi
if grep -q 'procd_set_param env GOMEMLIMIT=64MiB' "$FAKE/init.d/magitrickle"; then
  ok "the daemon got the limit"
else
  bad "the daemon did not get the limit: $(cat "$FAKE/init.d/magitrickle")"
fi
if [ -f "$FAKE/init.d/mihomo.mixomo-orig" ]; then ok "the original is kept"; else bad "the original is not kept"; fi

# The patch has to be idempotent: a second run must not add a second line.
sh "$FAKE/limit.sh" >/dev/null 2>&1
n=$(grep -c 'mixomo-gomemlimit' "$FAKE/init.d/mihomo")
if [ "$n" = "1" ]; then ok "the patch is idempotent"; else bad "the patch was applied twice ($n lines)"; fi

# The limit can be switched off.
cp "$FAKE/init.d/mihomo.mixomo-orig" "$FAKE/init.d/mihomo"
GOMEMLIMIT_CORE=0 GOMEMLIMIT_DAEMON=0 sh "$FAKE/limit.sh" >/dev/null 2>&1
if grep -q 'GOMEMLIMIT' "$FAKE/init.d/mihomo"; then
  bad "the limit was set although it was switched off"
else
  ok "the limit can be switched off"
fi

section "4. the lists that do not fit are switched off"

# A fake core: the rule-sets are not needed for this test.
mkdir -p "$FAKE/bin"
printf '#!/bin/sh\nexit 1\n' >"$FAKE/bin/mihomo"
chmod +x "$FAKE/bin/mihomo"

# Two lists: a small one and a big one.
seq 1 10  | sed 's/^/small.example./' >"$FAKE/small.txt"
seq 1 100 | sed 's/^/big.example./'   >"$FAKE/big.txt"
seq 1 200 | sed 's/^/ad.example./'    >"$FAKE/ad.txt"

# The lists are fetched by the script with curl. A small HTTP server is the
# easiest way to give it something it can fetch; without python3 the scheme
# of the files of the disk is used (curl reads them, and Linux is happy with
# it).
SERVER_PID=""
URL_BASE=""
if command -v python3 >/dev/null 2>&1; then
  PORT=18099
  (cd "$FAKE" && python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) &
  SERVER_PID=$!
  sleep 2
  if curl -sS --max-time 5 -o /dev/null "http://127.0.0.1:$PORT/small.txt"; then
    URL_BASE="http://127.0.0.1:$PORT"
  else
    URL_BASE=""
    kill "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
  fi
fi
if [ -n "$URL_BASE" ]; then
  url_of() { printf '%s/%s' "$URL_BASE" "$1"; }
else
  url_of() { printf 'file://%s/%s' "$FAKE" "$1"; }
fi
cleanup() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true; }
trap cleanup EXIT

cat >"$FAKE/template.yaml" <<EOF
configVersion: "0.1.4"

app:
  netfilter:
    disableIPv6: false

groups:
  - id: d9dce3ce
    name: "⭐ Custom"
    rules: []

subscriptions:
  - id: 11111111
    name: "Small"
    interface: Mihomo
    enable: true
    url: $(url_of small.txt)
    interval: 604800
    rules: []

  - id: 22222222
    name: "Big"
    interface: Mihomo
    enable: true
    url: $(url_of big.txt)
    interval: 604800
    rules: []

  - id: 33333333
    name: "🛡 Anti-AD"
    interface: blackhole
    enable: true
    url: $(url_of ad.txt)
    interval: 604800
    rules: []
EOF

# The state of one subscription in the state file. The id is used and not
# the name: the names have emojis in them, and a grep with a broken locale
# (the ru_RU.UTF-8 of Git Bash on Windows, for example) does not find them.
sub_enable() { # sub_enable <file> <id>
  awk -v n="$2" '
    index($0, "id: " n) > 0 { found = 1 }
    found && /^[[:space:]]*enable:/ { print $2; exit }
  ' "$1"
}

run_gen() { # run_gen <out> [env...]
  outf="$1"; shift
  env MIHOMO="$FAKE/bin/mihomo" RULE_DIR="$FAKE/empty" \
      CUSTOM_LIST="$FAKE/none.list" TEMPLATE="$FAKE/template.yaml" \
      OUT="$outf" "$@" sh "$GEN" >"$FAKE/gen.log" 2>&1
}

mkdir -p "$FAKE/empty"

if command -v curl >/dev/null 2>&1; then
  if run_gen "$FAKE/state.yaml" MAX_DOMAINS=50 PROBE=1; then
    ok "gen-mtrickle.sh runs with the limit"
  else
    bad "gen-mtrickle.sh failed: $(tail -3 "$FAKE/gen.log")"
  fi
  if [ "$(sub_enable "$FAKE/state.yaml" 11111111)" = "true" ]; then
    ok "the small list stays on"
  else
    bad "the small list was switched off"
  fi
  if [ "$(sub_enable "$FAKE/state.yaml" 22222222)" = "false" ]; then
    ok "the big list is switched off"
  else
    bad "the big list was not switched off"
  fi
  if grep -q 'Big' "$FAKE/gen.log"; then ok "the script says which list is too big"; else bad "the script does not name the list"; fi

  # A switched-off list must not be able to kill the router: the daemon
  # downloads a list when the user asks for an update in the web interface,
  # even when the subscription is off.
  url=$(awk '
    index($0, "id: 22222222") > 0 { found = 1 }
    found && /^[[:space:]]*url:/ { print $2; exit }
  ' "$FAKE/state.yaml")
  case "$url" in
    *big.txt) bad "the switched-off list kept its url ($url)" ;;
    "")       bad "the switched-off list has no url" ;;
    *)        ok "the switched-off list points to nothing ($url)" ;;
  esac
  if grep -q 'the original url:.*big.txt' "$FAKE/state.yaml"; then
    ok "the original url of the switched-off list is kept in a comment"
  else
    bad "the original url of the switched-off list is lost"
  fi
  if grep -q 'the list has 100 lines' "$FAKE/state.yaml"; then
    ok "the comment says why the list is switched off"
  else
    bad "the comment does not say why the list is switched off"
  fi

  # The limit can be switched off.
  if run_gen "$FAKE/state2.yaml" MAX_DOMAINS=0 PROBE=1 && [ "$(sub_enable "$FAKE/state2.yaml" 22222222)" = "true" ]; then
    ok "MAX_DOMAINS=0 switches the limit off"
  else
    bad "MAX_DOMAINS=0 did not switch the limit off"
  fi

  # The check can be switched off (no network, no lists).
  if run_gen "$FAKE/state3.yaml" MAX_DOMAINS=50 PROBE=0 && [ "$(sub_enable "$FAKE/state3.yaml" 22222222)" = "true" ]; then
    ok "PROBE=0 leaves the lists alone"
  else
    bad "PROBE=0 did not leave the lists alone"
  fi

  # The ad list is decided by the amount of RAM.
  if run_gen "$FAKE/state4.yaml" MAX_DOMAINS=5000 PROBE=1 ANTI_AD=0 && [ "$(sub_enable "$FAKE/state4.yaml" 33333333)" = "false" ]; then
    ok "ANTI_AD=0 switches the ad list off"
  else
    bad "ANTI_AD=0 did not switch the ad list off"
  fi
else
  skip "the size of the lists is not checked (no curl)"
fi

section "5. the groups"

if run_gen "$FAKE/state5.yaml" PROBE=0 GROUP_STEAM=1 GROUP_GITHUB=0; then
  ok "gen-mtrickle.sh runs with the groups"
else
  bad "gen-mtrickle.sh failed: $(tail -3 "$FAKE/gen.log")"
fi
if grep -A4 'c217a8bc' "$FAKE/state5.yaml" | grep -q 'enable: true'; then
  ok "the Steam group is on"
else
  bad "the Steam group is not on"
fi
if grep -A4 '89b87e29' "$FAKE/state5.yaml" | grep -q 'enable: false'; then
  ok "the GitHub group is off"
else
  bad "the GitHub group is not off"
fi
if grep -q '"id":"c217a8bc".*"enable":true' "$FAKE/state5.yaml.mtrickle"; then
  ok "the .mtrickle file has the state of the group"
else
  bad "the .mtrickle file has not the state of the group"
fi

# A wrong value has to be an error, not a silent "off".
if run_gen "$FAKE/state6.yaml" PROBE=0 GROUP_STEAM=maybe; then
  bad "a wrong value of a group was accepted"
else
  ok "a wrong value of a group is an error"
fi
if grep -q 'GROUP_STEAM must be 1 or 0' "$FAKE/gen.log"; then
  ok "the error names the variable"
else
  bad "the error does not name the variable: $(tail -2 "$FAKE/gen.log")"
fi

summary
