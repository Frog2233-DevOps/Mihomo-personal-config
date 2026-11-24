#!/usr/bin/env bash
# Script-level regression tests: port flags, scp fallback, busybox, API auth.
set -u
. "$(dirname "$0")/lib.sh"
cd "$ROOT"

section "1. POSIX and bash syntax"
for f in scripts/*.sh; do
  bash -n "$f" || bad "bash syntax: $f"
done
for f in scripts/apply-rulesets.sh scripts/build-ruleset.sh scripts/check-groups.sh scripts/update-rulesets.sh; do
  sh -n "$f" || bad "sh syntax: $f"
done
ok "shell syntax checked"

section "2. deploy.sh uses the right port flag for scp (functional test)"
STUB="$TMPDIR_TEST/bin"; mkdir -p "$STUB"; LOG="$TMPDIR_TEST/ssh-args"
cat > "$STUB/scp" <<EOF
#!/bin/sh
printf 'scp %s\n' "\$*" >> "$LOG"
exit 0
EOF
cat > "$STUB/ssh" <<EOF
#!/bin/sh
printf 'ssh %s\n' "\$*" >> "$LOG"
exit 0
EOF
chmod +x "$STUB/scp" "$STUB/ssh"
PATH="$STUB:$PATH" ROUTER_HOST=test-router ROUTER_PORT=2222 ROUTER_USER=root \
  APPLY=none SSH_KEY=/nonexistent bash scripts/deploy.sh >/dev/null 2>&1
if [ -f "$LOG" ]; then
  if grep -q '^scp .*-P 2222' "$LOG"; then ok "scp gets -P 2222"; else bad "scp port flag missing/wrong"; fi
  if grep -q '^ssh .*-p 2222' "$LOG"; then ok "ssh gets -p 2222"; else bad "ssh port flag missing"; fi
  if grep -q '^scp .*-O' "$LOG"; then ok "scp tries legacy -O for dropbear"; else bad "scp does not try -O"; fi
  if grep -q '^scp .*-p 2222' "$LOG"; then bad "scp still passed ssh-style -p"; else ok "scp has no ssh-style -p"; fi
  if grep -q 'stat local "2222"' "$LOG"; then bad "port parsed as a filename"; else ok "port is not a filename"; fi
else
  bad "deploy.sh did not call the stubs"
fi

section "3. build-ruleset.sh works under busybox"
lacks scripts/build-ruleset.sh "stat -c%s"
has scripts/build-ruleset.sh "wc -c < \"\$f\""

section "4. check-groups.sh validates the API answer"
has scripts/check-groups.sh '"proxies"'
has scripts/check-groups.sh '--header="Authorization: Bearer'
lacks scripts/check-groups.sh 'uclient-fetch -q -T 10 -o'

section "5. no secret is ever logged"
for f in scripts/apply-rulesets.sh scripts/check-groups.sh scripts/deploy.sh; do
  if grep -nE 'echo .*\$SECRET|printf .*\$SECRET|log .*\$SECRET' "$f" >/dev/null; then
    bad "$f may log the API secret"
  else
    ok "$f does not log the secret"
  fi
done

section "6. apply-rulesets modes are all handled"
for mode in reload restart none check; do
  has scripts/apply-rulesets.sh "$mode)"
done
has scripts/apply-rulesets.sh "configs?force=true"

section "7. update-rulesets keeps old files when the build fails"
has scripts/update-rulesets.sh "the old rule-sets stay in place"

summary
