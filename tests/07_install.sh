#!/usr/bin/env bash
# Regression tests for the one-command router installer.
set -u
. "$(dirname "$0")/lib.sh"
cd "$ROOT"

section "1. static checks"
check "install.sh has POSIX syntax" sh -n scripts/install.sh
if grep -q "\$'\\\\n'\|\[\[" scripts/install.sh; then bad "bashism in install.sh"; else ok "no bashisms in install.sh"; fi
if grep -nE 'echo .*\$SUB_URL|echo .*\$DASHBOARD_PASSWORD|log .*\$SUB_URL|log .*\$DASHBOARD_PASSWORD' scripts/install.sh >/dev/null; then
  bad "installer may log the URL or the secret"
else
  ok "installer does not log credentials"
fi
has scripts/install.sh "mktemp -d"
has scripts/install.sh "keeping the existing"

section "2. the embedded rule-set list matches the repository"
install_list() {
  awk '/^RULESETS=/{f=1} f{print} f && /ru steam telegram/{exit}' scripts/install.sh |
    tr -d '"' | sed 's/^RULESETS=//' | tr ' ' '\n' | grep -E '^[a-z0-9-]+$'
}
n_script=$(install_list | wc -l)
n_repo=$(ls ruleset/*.mrs | wc -l)
if [ "$n_script" -eq "$n_repo" ]; then ok "installer lists $n_script rule-sets (repo: $n_repo)"; else bad "installer lists $n_script, repo has $n_repo"; fi
for f in ruleset/*.mrs; do
  name=$(basename "$f" .mrs)
  if install_list | grep -qx "$name"; then :; else bad "installer misses $name"; fi
done

section "3. functional install from a local HTTP server (real script, real files)"
PORT=$(python3 - <<'PY'
import socket
s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()
PY
)
cd "$ROOT"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT" >"$TMPDIR_TEST/http.log" 2>&1 &
HTTP_PID=$!
trap 'kill "$HTTP_PID" 2>/dev/null || true' EXIT
sleep 2

DEST="$TMPDIR_TEST/router"
mkdir -p "$DEST"
SUB='https://sub.example.org/path?a=1&b=2|c'
PW='p@ss&|word\x'
BASE_URL="http://127.0.0.1:$PORT" ROOT="$DEST" VARIANT=full \
  SUB_URL="$SUB" DASHBOARD_PASSWORD="$PW" \
  sh scripts/install.sh >"$TMPDIR_TEST/install.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then ok "installer completed"; else bad "installer failed (rc=$rc): $(tail -5 "$TMPDIR_TEST/install.log")"; fi

check "config installed" test -f "$DEST/config/RU-Mihomo.yaml"
check "overwrite installed in backup" test -f "$DEST/backup/RU-Mihomo.conf"
check "overwrite installed at root" test -f "$DEST/RU-Mihomo.conf"
check "custom list installed" test -f "$DEST/lists/custom-domains.list"
for s in build-ruleset.sh update-rulesets.sh apply-rulesets.sh check-groups.sh; do
  check "script installed: $s" test -x "$DEST/scripts/$s"
done
cnt=$(ls "$DEST"/ruleset/*.mrs 2>/dev/null | wc -l)
if [ "$cnt" -eq 28 ]; then ok "28 rule-sets installed"; else bad "$cnt rule-sets installed"; fi

section "4. placeholders were substituted exactly (special characters)"
if grep -qF "url: '$SUB'" "$DEST/config/RU-Mihomo.yaml"; then ok "URL substituted verbatim"; else bad "URL substitution broken"; fi
if grep -qF "secret: $PW" "$DEST/config/RU-Mihomo.yaml"; then ok "secret substituted verbatim"; else bad "secret substitution broken"; fi
if grep -qF "mihomo:$PW" "$DEST/config/RU-Mihomo.yaml"; then ok "authentication substituted"; else bad "authentication substitution broken"; fi
if grep -qF "SUB_INFO_URL = $SUB" "$DEST/backup/RU-Mihomo.conf"; then ok "conf URL substituted"; else bad "conf URL substitution broken"; fi
if grep -qF "DASHBOARD_PASSWORD = $PW" "$DEST/backup/RU-Mihomo.conf"; then ok "conf password substituted"; else bad "conf password substitution broken"; fi
if grep -rq 'PASTE_SUBSCRIPTION_URL_HERE\|CHANGE_ME' "$DEST/config" "$DEST"/*.conf 2>/dev/null; then bad "placeholder left behind"; else ok "no placeholders left"; fi

section "5. credentials never appear in the transcript"
if grep -qF "$PW" "$TMPDIR_TEST/install.log" || grep -qF "$SUB" "$TMPDIR_TEST/install.log"; then
  bad "credentials leaked into the log"
else
  ok "credentials absent from the log"
fi

section "6. reinstall preserves user data and backs up changes"
printf '\n# my own domain\n' >> "$DEST/lists/custom-domains.list"
printf '# local edit\n' >> "$DEST/config/RU-Mihomo.yaml"
BASE_URL="http://127.0.0.1:$PORT" ROOT="$DEST" VARIANT=full \
  SUB_URL="$SUB" DASHBOARD_PASSWORD="$PW" \
  sh scripts/install.sh >"$TMPDIR_TEST/reinstall.log" 2>&1
if grep -q 'keeping the existing' "$TMPDIR_TEST/reinstall.log"; then ok "custom list kept"; else bad "custom list overwritten"; fi
if grep -q '# my own domain' "$DEST/lists/custom-domains.list"; then ok "user domain survived"; else bad "user domain lost"; fi
if [ -f "$DEST/config/RU-Mihomo.yaml.bak" ] && grep -q '# local edit' "$DEST/config/RU-Mihomo.yaml.bak"; then ok "previous config backed up"; else bad "no config backup"; fi

section "7. variants and atomic failure"
for v in lite smart; do
  D="$TMPDIR_TEST/router-$v"; mkdir -p "$D"
  BASE_URL="http://127.0.0.1:$PORT" ROOT="$D" VARIANT="$v" \
    SUB_URL="$SUB" DASHBOARD_PASSWORD="$PW" \
    sh scripts/install.sh >"$TMPDIR_TEST/install-$v.log" 2>&1
  check "variant $v installed" test -f "$D/config/RU-Mihomo-$v.yaml"
done

D="$TMPDIR_TEST/router-fail"; mkdir -p "$D"
BASE_URL="http://127.0.0.1:1" ROOT="$D" VARIANT=full \
  SUB_URL="$SUB" DASHBOARD_PASSWORD="$PW" \
  sh scripts/install.sh >"$TMPDIR_TEST/fail.log" 2>&1
if [ -f "$D/config/RU-Mihomo.yaml" ] || [ -f "$D/ruleset/ru.mrs" ]; then
  bad "a failed download left files behind"
else
  ok "failed download changed nothing"
fi

section "8. a custom ROOT works without root privileges"
if command -v runuser >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
  D="$TMPDIR_TEST/router-nonroot"; mkdir -p "$D"; chmod 777 "$D"
  runuser -u nobody -- env ROOT="$D" BASE_URL="http://127.0.0.1:$PORT" \
    VARIANT=full SUB_URL="$SUB" DASHBOARD_PASSWORD="$PW" \
    sh "$ROOT/scripts/install.sh" >"$TMPDIR_TEST/nonroot.log" 2>&1
  if [ -f "$D/config/RU-Mihomo.yaml" ]; then ok "installed as nobody into a custom ROOT"; else bad "non-root install failed: $(tail -2 "$TMPDIR_TEST/nonroot.log")"; fi
else
  skip "non-root check (already non-root or no runuser)"
fi

section "9. the installer sets up the daily cron without duplicates"
CRONDIR="$TMPDIR_TEST/cronbin"; mkdir -p "$CRONDIR"
CRONLOG="$TMPDIR_TEST/crontab.log"; : > "$CRONLOG"
CRONSTATE="$TMPDIR_TEST/cronstate"
printf '%s\n' '0 1 * * * /usr/bin/true' > "$CRONSTATE"
cat > "$CRONDIR/crontab" <<EOF
#!/bin/sh
if [ "\$1" = "-l" ]; then cat "$CRONSTATE"; exit 0; fi
cat "\$1" > "$CRONSTATE"
cat "\$1" >> "$CRONLOG"
EOF
chmod +x "$CRONDIR/crontab"
D="$TMPDIR_TEST/router-cron"; mkdir -p "$D"
for run in 1 2; do
  PATH="$CRONDIR:$PATH" BASE_URL="http://127.0.0.1:$PORT" ROOT="$D" \
    VARIANT=full ENABLE_CRON=1 SUB_URL="$SUB" DASHBOARD_PASSWORD="$PW" \
    sh scripts/install.sh >"$TMPDIR_TEST/cron-$run.log" 2>&1
done
if grep -qF '0 1 * * * /usr/bin/true' "$CRONLOG"; then ok "existing cron entries kept"; else bad "existing crontab entries lost"; fi
if [ "$(grep -c 'update-rulesets.sh' "$CRONSTATE")" -eq 1 ]; then
  ok "one cron line after two installs (no duplicates)"
else
  bad "cron line count wrong: $(grep -c 'update-rulesets.sh' "$CRONSTATE")"
fi
if grep -qF "$D/scripts/update-rulesets.sh" "$CRONLOG"; then ok "cron points at the installed script"; else bad "cron path wrong"; fi
if grep -q 'cron installed' "$TMPDIR_TEST/cron-1.log"; then ok "cron setup reported"; else bad "cron setup not reported"; fi

D="$TMPDIR_TEST/router-nocron"; mkdir -p "$D"
BASE_URL="http://127.0.0.1:$PORT" ROOT="$D" VARIANT=full ENABLE_CRON=0 \
  SUB_URL="$SUB" DASHBOARD_PASSWORD="$PW" \
  sh scripts/install.sh >"$TMPDIR_TEST/nocron.log" 2>&1
if grep -q 'cron was not installed' "$TMPDIR_TEST/nocron.log"; then ok "ENABLE_CRON=0 respected"; else bad "ENABLE_CRON=0 ignored"; fi

section "10. the OpenClash settings are written through uci"
UCI_DIR="$TMPDIR_TEST/uci"
mkdir -p "$UCI_DIR"
: > "$UCI_DIR/openclash"
cat > "$TMPDIR_TEST/bin_uci" <<'UCI'
#!/bin/sh
# A fake uci: it keeps the calls in a log and answers "get" from the log.
LOG="$FAKE_UCI_LOG"
STORE="$FAKE_UCI_STORE"
shift 2>/dev/null   # drop -q
cmd="$1"; shift
case "$cmd" in
  set)    echo "set $*" >> "$LOG"; echo "$*" >> "$STORE" ;;
  add)    echo "add $*" >> "$LOG"; echo "subscribe_info[0]" ;;
  delete) echo "delete $*" >> "$LOG" ;;
  add_list) echo "add_list $*" >> "$LOG"; echo "$*" >> "$STORE" ;;
  commit) echo "commit $*" >> "$LOG" ;;
  get)
    key="$1"
    v="$(grep -F "$key=" "$STORE" 2>/dev/null | tail -1 | cut -d= -f2-)"
    [ -n "$v" ] || exit 1
    echo "$v"
    ;;
esac
exit 0
UCI
mkdir -p "$TMPDIR_TEST/fakebin"
cp "$TMPDIR_TEST/bin_uci" "$TMPDIR_TEST/fakebin/uci"
chmod +x "$TMPDIR_TEST/fakebin/uci"
: > "$TMPDIR_TEST/uci.log"
: > "$TMPDIR_TEST/uci.store"
D="$TMPDIR_TEST/router-uci"; mkdir -p "$D"
PATH="$TMPDIR_TEST/fakebin:$PATH" FAKE_UCI_LOG="$TMPDIR_TEST/uci.log" FAKE_UCI_STORE="$TMPDIR_TEST/uci.store" \
  BASE_URL="http://127.0.0.1:$PORT" ROOT="$D" VARIANT=full UCI_CONFIG="$UCI_DIR/openclash" \
  CONFIGURE_OPENCLASH=1 \
  SUB_URL="$SUB" DASHBOARD_PASSWORD="$PW" \
  sh scripts/install.sh >"$TMPDIR_TEST/uci-install.log" 2>&1
if grep -qF "openclash.config.dashboard_password=$PW" "$TMPDIR_TEST/uci.log"; then
  ok "the dashboard password was written"
else
  bad "the dashboard password was not written"
fi
if grep -qF "openclash.config.config_path=$D/config/RU-Mihomo.yaml" "$TMPDIR_TEST/uci.log"; then
  ok "the config path was written"
else
  bad "the config path was not written"
fi
if grep -qF "url=$SUB" "$TMPDIR_TEST/uci.log"; then
  ok "the subscription was written"
else
  bad "the subscription was not written"
fi
if grep -q "commit openclash" "$TMPDIR_TEST/uci.log"; then
  ok "the settings were committed"
else
  bad "the settings were not committed"
fi
if [ -f "$UCI_DIR/openclash.bak."* ]; then
  ok "the old settings were backed up"
else
  bad "no backup of the settings"
fi
if grep -qF "openclash.config_overwrite" "$TMPDIR_TEST/uci.log"; then
  ok "the overwrite file got its own UCI section"
else
  bad "no config_overwrite section"
fi
if grep -qF "enable=1" "$TMPDIR_TEST/uci.log"; then
  ok "the overwrite section is enabled"
else
  bad "the overwrite section is not enabled"
fi
if [ -f "$D/overwrite/RU-Mihomo.conf" ]; then
  ok "the overwrite file lies in overwrite/"
else
  bad "the overwrite file is not in overwrite/"
fi

kill "$HTTP_PID" 2>/dev/null || true
trap - EXIT
cd "$ROOT"
summary
