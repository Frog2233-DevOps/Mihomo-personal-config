#!/usr/bin/env bash
# The guard of the IPv6 of the tunnel device: it has to enable IPv6 on the
# device "Mihomo" and to start MagiTrickle again, and it has to survive the
# moment when the tunnel creates the device once more.
set -u
. "$(dirname "$0")/lib.sh"
cd "$ROOT"

GUARD=scripts/mixomo-ipv6.sh
INIT=scripts/mixomo-ipv6.init

section "1. the files of the fix"

for f in "$GUARD" "$INIT"; do
  if [ -f "$f" ]; then ok "$f exists"; else bad "$f is missing"; fi
  if sh -n "$f" 2>/dev/null; then ok "$f passes sh -n"; else bad "$f has a syntax error"; fi
  if grep -qE '\[\[[^:]|source |<<<' "$f"; then bad "$f uses bash syntax"; else ok "$f has no bash syntax"; fi
done

# The order at the boot: the tunnel (START=99) has to be up before the guard.
if grep -q '^START=99' "$INIT"; then ok "the init script starts at 99"; else bad "the init script does not start at 99"; fi
if grep -q 'procd_open_instance' "$INIT"; then ok "the init script runs as a service"; else bad "the init script has no instance"; fi
if grep -q 'procd_set_param respawn' "$INIT"; then ok "the instance is respawned"; else bad "the instance is not respawned"; fi
if grep -q 'extra_command' "$INIT"; then ok "the init script has its own commands"; else bad "the init script has no own commands"; fi
# The switch that turns the fix off.
if grep -q 'FIX_IPV6' "$GUARD"; then ok "the guard knows FIX_IPV6"; else bad "the guard does not know FIX_IPV6"; fi
# The device of the tunnel.
if grep -q 'Mihomo' "$GUARD"; then ok "the guard knows the device"; else bad "the guard does not know the device"; fi

section "2. the report of the state"

# A fake router: a device, a knob and a service.
FAKE="$TMPDIR_TEST/fake"
mkdir -p "$FAKE/net/Mihomo" "$FAKE/sys/Mihomo"
printf '1\n' >"$FAKE/sys/Mihomo/disable_ipv6"

cat >"$FAKE/magitrickle" <<EOF
#!/bin/sh
# The fake service of MagiTrickle: it remembers what it was asked to do.
echo "\$1" >>"$FAKE/magitrickle.log"
case "\$1" in
  running) [ -f "$FAKE/magitrickle.running" ] && exit 0 || exit 1 ;;
  start|restart) touch "$FAKE/magitrickle.running" ;;
esac
exit 0
EOF
chmod +x "$FAKE/magitrickle"

ENV="MIXOMO_NET_DIR=$FAKE/net MIXOMO_SYS_DIR=$FAKE/sys MIXOMO_MAGITRICKLE=$FAKE/magitrickle MIXOMO_CONF=$FAKE/mixomo.conf"

out=$(env $ENV sh "$GUARD" status 2>&1)
if printf '%s' "$out" | grep -q 'device Mihomo: exists'; then
  ok "the report says that the device exists"
else
  bad "the report does not mention the device: $out"
fi
if printf '%s' "$out" | grep -q 'disable_ipv6 = 1'; then
  ok "the report shows the value of the knob"
else
  bad "the report does not show the value of the knob: $out"
fi
if printf '%s' "$out" | grep -q 'magitrickle: not running'; then
  ok "the report says that MagiTrickle is not running"
else
  bad "the report does not mention MagiTrickle: $out"
fi

section "3. the fix"

env $ENV sh "$GUARD" fix >"$TMPDIR_TEST/fix.log" 2>&1
if [ "$(tr -d ' \t\r\n' <"$FAKE/sys/Mihomo/disable_ipv6")" = "0" ]; then
  ok "IPv6 is enabled on the device"
else
  bad "IPv6 is still disabled on the device"
fi
if [ -f "$FAKE/magitrickle.running" ]; then
  ok "MagiTrickle was started"
else
  bad "MagiTrickle was not started"
fi
if grep -q 'start' "$FAKE/magitrickle.log"; then ok "the service was asked to start"; else bad "the service was not asked to start"; fi

# The fix has to be idempotent: a second run changes nothing.
env $ENV sh "$GUARD" fix >/dev/null 2>&1
if [ "$(tr -d ' \t\r\n' <"$FAKE/sys/Mihomo/disable_ipv6")" = "0" ]; then
  ok "the fix is idempotent"
else
  bad "the second run of the fix changed the knob"
fi

section "4. the tunnel creates the device once more"

# The tunnel is restarted: the device is new and IPv6 is disabled on it again.
printf '1\n' >"$FAKE/sys/Mihomo/disable_ipv6"
rm -f "$FAKE/magitrickle.running"
env $ENV sh "$GUARD" fix >/dev/null 2>&1
if [ "$(tr -d ' \t\r\n' <"$FAKE/sys/Mihomo/disable_ipv6")" = "0" ]; then
  ok "the device is repaired after a restart of the tunnel"
else
  bad "the device was not repaired after a restart of the tunnel"
fi
if [ -f "$FAKE/magitrickle.running" ]; then
  ok "MagiTrickle was started again"
else
  bad "MagiTrickle was not started again"
fi

section "5. the fix can be switched off"

printf '1\n' >"$FAKE/sys/Mihomo/disable_ipv6"
rm -f "$FAKE/magitrickle.running"
FIX_IPV6=0 env $ENV sh "$GUARD" fix >"$TMPDIR_TEST/off.log" 2>&1
if [ "$(tr -d ' \t\r\n' <"$FAKE/sys/Mihomo/disable_ipv6")" = "1" ]; then
  ok "FIX_IPV6=0 leaves the device alone"
else
  bad "FIX_IPV6=0 changed the knob"
fi
if [ -f "$FAKE/magitrickle.running" ]; then
  bad "FIX_IPV6=0 started MagiTrickle anyway"
else
  ok "FIX_IPV6=0 does not start MagiTrickle"
fi

# The same through the settings file of the router.
printf 'FIX_IPV6=0\n' >"$FAKE/mixomo.conf"
env $ENV sh "$GUARD" fix >/dev/null 2>&1
if [ "$(tr -d ' \t\r\n' <"$FAKE/sys/Mihomo/disable_ipv6")" = "1" ]; then
  ok "the settings file of the router switches the fix off"
else
  bad "the settings file of the router did not switch the fix off"
fi
rm -f "$FAKE/mixomo.conf"

section "6. the guard repairs the device in the background"

printf '1\n' >"$FAKE/sys/Mihomo/disable_ipv6"
rm -f "$FAKE/magitrickle.running"
env $ENV MIXOMO_IPV6_INTERVAL=1 MIXOMO_IPV6_WAIT=5 \
  sh "$GUARD" guard >"$TMPDIR_TEST/guard.log" 2>&1 &
GUARD_PID=$!
sleep 6
# The tunnel was restarted in the meantime.
printf '1\n' >"$FAKE/sys/Mihomo/disable_ipv6"
sleep 4
kill "$GUARD_PID" 2>/dev/null || true
wait "$GUARD_PID" 2>/dev/null || true
if [ "$(tr -d ' \t\r\n' <"$FAKE/sys/Mihomo/disable_ipv6")" = "0" ]; then
  ok "the guard repaired the device on its own"
else
  bad "the guard did not repair the device"
fi
if [ -f "$FAKE/magitrickle.running" ]; then
  ok "the guard started MagiTrickle"
else
  bad "the guard did not start MagiTrickle"
fi

section "7. the device that is not there"

rm -rf "$FAKE/net/Mihomo"
out=$(env $ENV MIXOMO_IPV6_WAIT=1 sh "$GUARD" status 2>&1)
if printf '%s' "$out" | grep -q 'device Mihomo: missing'; then
  ok "the report says that the device is missing"
else
  bad "the report does not say that the device is missing: $out"
fi

summary
