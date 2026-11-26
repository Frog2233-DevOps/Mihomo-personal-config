#!/usr/bin/env sh
# =============================================================================
#  mixomo-ipv6.sh - keep IPv6 alive on the tunnel device of the mixomo scheme
# =============================================================================
#  The problem
#  ----------
#  The tunnel device "Mihomo" is created by hev-socks5-tunnel. A new device
#  inherits net.ipv6.conf.default.disable_ipv6 from the kernel, so on a router
#  with IPv6 switched off the device comes up with IPv6 disabled:
#
#      sysctl net.ipv6.conf.Mihomo.disable_ipv6   ->  1
#
#  MagiTrickle links its address sets to that device and adds a default route
#  for it. The kernel refuses the IPv6 route of a device with IPv6 disabled
#  and answers -EACCES, so the daemon gives up and dies:
#
#      failed to enable group: failed to link ipset to interface:
#      error adding iface route: permission denied
#
#  The fix
#  -------
#  IPv6 is enabled on this one device (never globally) and MagiTrickle is
#  started again. The device is created again at every start of the tunnel
#  and comes up with IPv6 disabled once more, so the state is checked
#  periodically and repaired when it is needed.
#
#  Usage on the router:
#      sh /etc/mihomo/scripts/mixomo-ipv6.sh status   # the report
#      sh /etc/mihomo/scripts/mixomo-ipv6.sh fix      # the fix, once
#      sh /etc/mihomo/scripts/mixomo-ipv6.sh guard    # the loop (the init
#                                                    # script runs this one)
#
#  Environment variables:
#      MIXOMO_TUN_DEVICE     the name of the device (default: Mihomo)
#      FIX_IPV6              1 (default) enables the fix, 0 switches it off
#      MIXOMO_IPV6_WAIT      how long to wait for the device, in seconds
#                            (default: 60)
#      MIXOMO_IPV6_INTERVAL  how often the state is checked, in seconds
#                            (default: 30)
#      MIXOMO_CONF          the file with the settings
#                            (default: /etc/mihomo/mixomo.conf)
#      MIXOMO_NET_DIR       where the devices are
#                            (default: /sys/class/net)
#      MIXOMO_SYS_DIR       where the knobs of the IPv6 are
#                            (default: /proc/sys/net/ipv6/conf)
#      MIXOMO_MAGITRICKLE   the init script of MagiTrickle
#                            (default: /etc/init.d/magitrickle)
#
#  The last three are for the tests: the script can be checked without a
#  router and without the real device.
#
#  POSIX sh (busybox ash on the router), no bash.
# =============================================================================
set -u

# The values of the environment are remembered before the defaults are put on
# top of them: the environment has the priority over the settings file.
DEVICE_ENV="${MIXOMO_TUN_DEVICE:-}"
FIX_IPV6_ENV="${FIX_IPV6:-}"

DEVICE="${DEVICE_ENV:-Mihomo}"
FIX_IPV6="${FIX_IPV6_ENV:-1}"
WAIT="${MIXOMO_IPV6_WAIT:-60}"
INTERVAL="${MIXOMO_IPV6_INTERVAL:-30}"
CONF="${MIXOMO_CONF:-/etc/mihomo/mixomo.conf}"
NET_DIR="${MIXOMO_NET_DIR:-/sys/class/net}"
SYS_DIR="${MIXOMO_SYS_DIR:-/proc/sys/net/ipv6/conf}"
MT_INIT="${MIXOMO_MAGITRICKLE:-/etc/init.d/magitrickle}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# --- the settings file --------------------------------------------------------
# The file is read, not executed: a line is "KEY=VALUE", the value is taken
# as it is. The environment has the priority over the file.
read_conf() {
  [ -f "$CONF" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    key=${line%%=*}
    val=${line#*=}
    [ "$key" = "$line" ] && continue
    case "$key" in
      FIX_IPV6)             [ -n "${FIX_IPV6_ENV:-}" ] || FIX_IPV6="$val" ;;
      MIXOMO_TUN_DEVICE)    [ -n "${DEVICE_ENV:-}" ] || DEVICE="$val" ;;
      MIXOMO_IPV6_WAIT)     WAIT="$val" ;;
      MIXOMO_IPV6_INTERVAL) INTERVAL="$val" ;;
    esac
  done <"$CONF"
}

# The file is read after the defaults are set: the values of the environment
# (DEVICE_ENV, FIX_IPV6_ENV) have the priority over the file.
read_conf

SYSCTL_PATH="$SYS_DIR/$DEVICE/disable_ipv6"

device_exists() { [ -e "$NET_DIR/$DEVICE" ]; }

# The value of the knob, empty when it cannot be read.
ipv6_disabled() {
  [ -r "$SYSCTL_PATH" ] || return 1
  tr -d ' \t\r\n' <"$SYSCTL_PATH" 2>/dev/null || true
}

# IPv6 on this one device. The procfs is written directly - busybox sysctl
# is not everywhere - and sysctl is the fallback.
ipv6_enable() {
  if [ -w "$SYSCTL_PATH" ]; then
    if printf '0\n' >"$SYSCTL_PATH" 2>/dev/null; then return 0; fi
  fi
  command -v sysctl >/dev/null 2>&1 || return 1
  sysctl -w "net.ipv6.conf.$DEVICE.disable_ipv6=0" >/dev/null 2>&1
}

magitrickle_installed() { [ -x "$MT_INIT" ]; }

magitrickle_running() {
  magitrickle_installed || return 0
  "$MT_INIT" running >/dev/null 2>&1
}

# MagiTrickle is started when it is not running. The daemon dies at once when
# the IPv6 of the device is disabled, so this is also the answer to the crash
# loop of procd.
ensure_magitrickle() {
  magitrickle_installed || return 0
  if magitrickle_running; then return 0; fi
  log "magitrickle is not running - starting it"
  "$MT_INIT" start >/dev/null 2>&1 || \
    "$MT_INIT" restart >/dev/null 2>&1 || true
  sleep 2
  if magitrickle_running; then
    log "magitrickle is running again"
  else
    log "WARNING: magitrickle did not start - see the log of the service"
  fi
}

wait_for_device() {
  i=0
  while [ "$i" -lt "$WAIT" ]; do
    device_exists && return 0
    sleep 1
    i=$((i + 1))
  done
  return 1
}

# The fix itself: IPv6 on the device, then MagiTrickle.
apply_fix() {
  if ! device_exists; then
    log "the device $DEVICE does not exist"
    return 1
  fi
  if [ "$(ipv6_disabled)" != "0" ]; then
    if ipv6_enable; then
      log "IPv6 is enabled on $DEVICE"
    else
      log "ERROR: cannot enable IPv6 on $DEVICE"
      return 1
    fi
  fi
  ensure_magitrickle
  return 0
}

# --- the modes ----------------------------------------------------------------
do_status() {
  printf 'device %s: %s\n' "$DEVICE" \
    "$(device_exists && echo 'exists' || echo 'missing')"
  if device_exists; then
    v=$(ipv6_disabled)
    printf '  net.ipv6.conf.%s.disable_ipv6 = %s\n' "$DEVICE" "${v:-unknown}"
  fi
  if magitrickle_installed; then
    printf 'magitrickle: %s\n' \
      "$(magitrickle_running && echo 'running' || echo 'not running')"
  else
    printf 'magitrickle: not installed\n'
  fi
  printf 'fix: %s\n' "$([ "$FIX_IPV6" = "0" ] && echo 'off' || echo 'on')"
}

do_fix() {
  if [ "$FIX_IPV6" = "0" ]; then
    log "the fix is switched off (FIX_IPV6=0)"
    return 0
  fi
  if ! wait_for_device; then
    log "the device $DEVICE did not appear in ${WAIT}s"
    return 1
  fi
  apply_fix
}

# The loop: the device is created again at every start of the tunnel and comes
# up with IPv6 disabled once more, so the state is checked and repaired.
do_guard() {
  if [ "$FIX_IPV6" = "0" ]; then
    log "the fix is switched off (FIX_IPV6=0) - nothing to do"
    return 0
  fi
  log "the guard of the IPv6 of $DEVICE is started"
  if wait_for_device; then
    apply_fix || true
  else
    log "the device $DEVICE did not appear in ${WAIT}s - the tunnel is not running?"
  fi
  while :; do
    sleep "$INTERVAL"
    [ "$FIX_IPV6" = "0" ] && continue
    if device_exists && [ "$(ipv6_disabled)" != "0" ]; then
      log "the device was created again - IPv6 is disabled on it"
      apply_fix || true
    fi
    ensure_magitrickle
  done
}

case "${1:-guard}" in
  guard)  do_guard ;;
  fix)    do_fix ;;
  status) do_status ;;
  *)      printf 'usage: %s [guard|fix|status]\n' "$0" >&2; exit 1 ;;
esac
