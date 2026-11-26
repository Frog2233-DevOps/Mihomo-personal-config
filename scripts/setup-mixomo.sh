#!/usr/bin/env sh
# =============================================================================
#  setup-mixomo.sh - set up the mixomo scheme on an OpenWrt router
# =============================================================================
#  The mixomo scheme sends only the selected traffic through the core:
#
#      MagiTrickle answers the DNS, marks the addresses of its lists, and
#      only the marked traffic goes into the core (through the tun device of
#      hev-socks5-tunnel). Everything else goes to the provider at full
#  speed and never touches the core.
#
#  That is the answer to the two problems of the "everything through the
#  core" layout: the speed loss and the UDP timeouts.
#
#  Run on the router, after mixomo is installed:
#
#      curl -fsSL -o /tmp/setup-mixomo.sh \
#        https://raw.githubusercontent.com/Frog2233-DevOps/Mihomo-personal-config/main/scripts/setup-mixomo.sh
#      SUB_URL='https://provider/subscribe' DASHBOARD_PASSWORD='your-password' \
#        sh /tmp/setup-mixomo.sh
#
#  Read /tmp/setup-mixomo.sh before running it - it comes from the network.
#
#  Environment variables:
#      SUB_URL            required - the subscription URL
#      DASHBOARD_PASSWORD required - the mihomo API / dashboard secret
#      REPO               owner/repo, for forks
#      BRANCH             main (default) or dev
#      BASE_URL           override the download root (for local testing)
#      MIHOMO_DIR         the layout of mixomo (default: /etc/mihomo)
#      MAGITRICKLE_DIR    the state of MagiTrickle
#                         (default: /etc/magitrickle)
#      STOP_OPENCLASH     1 (default) stops and disables OpenClash - the two
#                         schemes fight over the routing table; 0 leaves it
#                         running (the traffic then goes through both)
#      INSTALL_MIXOMO     1 installs mixomo when it is missing (it is not
#                         installed by default: it is somebody else's
#                         software and its installer asks questions)
#      MAGITRICKLE        original (default) or mod - only used when
#                         INSTALL_MIXOMO=1
#      ENABLE_CRON        install the daily rule-set job (default: 1)
#      CHECKS             1 (default) runs the checks at the end and fails
#                         when a service is not running; 0 installs and stops
#                         before the checks
#
#  Nothing is changed until every file has been downloaded.
# =============================================================================
set -eu

MIHOMO_DIR="${MIHOMO_DIR:-/etc/mihomo}"
MAGITRICKLE_DIR="${MAGITRICKLE_DIR:-/etc/magitrickle}"
REPO="${REPO:-Frog2233-DevOps/Mihomo-personal-config}"
BRANCH="${BRANCH:-main}"
SUB_URL="${SUB_URL:-}"
DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD:-}"
BASE_URL="${BASE_URL:-}"
STOP_OPENCLASH="${STOP_OPENCLASH:-1}"
INSTALL_MIXOMO="${INSTALL_MIXOMO:-0}"
MAGITRICKLE="${MAGITRICKLE:-original}"
# The ports that must not touch the core, separated by spaces or commas
# (for example: "25565 28015"). They are written into
# /etc/mihomo/bypass-ports.txt, which belongs to the user afterwards.
BYPASS_PORTS="${BYPASS_PORTS:-}"
ENABLE_CRON="${ENABLE_CRON:-1}"
CHECKS="${CHECKS:-1}"

# The rule-sets the core of this scheme uses. Keep in sync with ruleset/ -
# tests/09_mixomo.sh checks this list against the repository.
RULESETS="anthropic anti-ad apple category-ai-ru category-games category-ru cdn
custom-domains discord facebook fake-ip-filter github google-gemini instagram
microsoft netflix openai private rkn-blocked-ip rkn-blocked rkn-community roblox
ru steam telegram twitter xai youtube"

log()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -n "$SUB_URL" ] || fail "set SUB_URL to your subscription URL"
[ -n "$DASHBOARD_PASSWORD" ] || fail "set DASHBOARD_PASSWORD (it must not be empty)"
[ "$(id -u)" = "0" ] || fail "run as root"

# --- the mixomo layout must be there ------------------------------------------
mixomo_present() {
  command -v mihomo >/dev/null 2>&1 || [ -x /usr/bin/mihomo ] || return 1
  [ -x /etc/init.d/magitrickle ] || return 1
  [ -x /etc/init.d/hev-socks5-tunnel ] || return 1
  return 0
}

if ! mixomo_present; then
  if [ "$INSTALL_MIXOMO" = "1" ]; then
    log "installing mixomo (this asks no questions, MAGITRICKLE=$MAGITRICKLE)"
    curl -fsSL https://github.com/Internet-Helper/mixomo-openwrt/raw/main/install.sh \
      | MAGITRICKLE="$MAGITRICKLE" sh
    mixomo_present || fail "mixomo is still not complete after the installation"
  else
    log "mixomo is not installed. Install it first:"
    log "  curl -fsSL https://github.com/Internet-Helper/mixomo-openwrt/raw/main/install.sh | sh"
    log "or run this script again with INSTALL_MIXOMO=1."
    exit 1
  fi
fi

CORE="/usr/bin/mihomo"
[ -x "$CORE" ] || CORE="$(command -v mihomo 2>/dev/null || true)"
[ -n "$CORE" ] || fail "no core found"

# --- downloader ---------------------------------------------------------------
DL=""
for c in curl uclient-fetch wget; do
  if command -v "$c" >/dev/null 2>&1; then DL="$c"; break; fi
done
[ -n "$DL" ] || fail "no curl, uclient-fetch or wget found"

if [ -n "$BASE_URL" ]; then
  BASES="$BASE_URL"
else
  BASES="https://raw.githubusercontent.com/$REPO/$BRANCH https://cdn.jsdelivr.net/gh/$REPO@$BRANCH https://gh-proxy.com/https://raw.githubusercontent.com/$REPO/$BRANCH"
fi

fetch_one() { # fetch_one <url> <dest>
  case "$DL" in
    curl)          curl -fsSL --retry 1 --connect-timeout 15 --max-time 180 "$1" -o "$2" ;;
    uclient-fetch) uclient-fetch -q -T 20 -O "$2" "$1" ;;
    wget)          wget -q -O "$2" "$1" ;;
  esac
}

fetch() { # fetch <relative path> <dest>
  for base in $BASES; do
    rm -f "$2"
    if fetch_one "$base/$1" "$2" 2>/dev/null && [ -s "$2" ]; then return 0; fi
  done
  return 1
}

esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# --- download everything ------------------------------------------------------
TMP="$(mktemp -d /tmp/setup-mixomo.XXXXXX)" || fail "cannot create a temp directory"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/ruleset" "$TMP/scripts"

log "downloading the scheme from $REPO@$BRANCH"
fetch "RU-Mihomo-mixomo.yaml" "$TMP/config.yaml" || fail "cannot download RU-Mihomo-mixomo.yaml"
fetch "magitrickle/magitrickle.yaml" "$TMP/magitrickle.yaml" || fail "cannot download magitrickle/magitrickle.yaml"
for s in build-ruleset.sh gen-mtrickle.sh update-mixomo.sh apply-rulesets.sh check-groups.sh bypass-ports.sh; do
  fetch "scripts/$s" "$TMP/scripts/$s" || fail "cannot download scripts/$s"
done
fetch "scripts/mixomo-bypass.init" "$TMP/scripts/mixomo-bypass.init" || fail "cannot download scripts/mixomo-bypass.init"
fetch "lists/custom-domains.list" "$TMP/custom-domains.list" || fail "cannot download the custom list"
fetch "lists/bypass-ports.list" "$TMP/bypass-ports.list" || fail "cannot download the bypass list"

for r in $RULESETS; do
  fetch "ruleset/$r.mrs" "$TMP/ruleset/$r.mrs" || fail "cannot download ruleset/$r.mrs"
done

sed -i "s|PASTE_SUBSCRIPTION_URL_HERE|$(esc "$SUB_URL")|g;
        s|CHANGE_ME|$(esc "$DASHBOARD_PASSWORD")|g" "$TMP/config.yaml"

if grep -q 'PASTE_SUBSCRIPTION_URL_HERE\|CHANGE_ME' "$TMP/config.yaml"; then
  fail "a placeholder is left in the config"
fi

# --- OpenClash has to go ------------------------------------------------------
# Both schemes redirect the traffic of the clients. Together they fight over
# the routing table and the result is a connection that goes nowhere.
if [ "$STOP_OPENCLASH" = "1" ] && [ -x /etc/init.d/openclash ]; then
  if [ -f /etc/config/openclash ]; then
    cp /etc/config/openclash "/etc/config/openclash.bak.$$" || fail "cannot back up the OpenClash settings"
    log "OpenClash settings backed up to /etc/config/openclash.bak.$$"
  fi
  /etc/init.d/openclash stop >/dev/null 2>&1 || true
  /etc/init.d/openclash disable >/dev/null 2>&1 || true
  log "OpenClash stopped and disabled (start it again with: service openclash enable)"
elif [ -x /etc/init.d/openclash ]; then
  log "WARNING: OpenClash is still enabled and will fight with this scheme"
fi

# --- install ------------------------------------------------------------------
mkdir -p "$MIHOMO_DIR/rule-files" "$MIHOMO_DIR/proxy-providers" "$MIHOMO_DIR/scripts" \
         "$MIHOMO_DIR/lists" "$MIHOMO_DIR/backup" "$MAGITRICKLE_DIR/state" || fail "cannot create the directories"

if [ -f "$MIHOMO_DIR/config.yaml" ]; then
  cp "$MIHOMO_DIR/config.yaml" "$MIHOMO_DIR/config.yaml.bak" || fail "cannot back up the config"
fi
cp "$TMP/config.yaml" "$MIHOMO_DIR/config.yaml" || fail "cannot install the config"
log "config installed: $MIHOMO_DIR/config.yaml"

for s in build-ruleset.sh gen-mtrickle.sh update-mixomo.sh apply-rulesets.sh check-groups.sh bypass-ports.sh; do
  cp "$TMP/scripts/$s" "$MIHOMO_DIR/scripts/$s" || fail "cannot install scripts/$s"
  chmod +x "$MIHOMO_DIR/scripts/$s" || fail "cannot chmod scripts/$s"
done

# The init script that keeps the bypass rule in front of the chains of
# MagiTrickle.
cp "$TMP/scripts/mixomo-bypass.init" /etc/init.d/mixomo-bypass || fail "cannot install the init script"
chmod +x /etc/init.d/mixomo-bypass || fail "cannot chmod the init script"
if [ -x /etc/init.d/mixomo-bypass ]; then
  /etc/init.d/mixomo-bypass enable >/dev/null 2>&1 || true
fi

# The list of the ports belongs to the user: never overwrite it.
if [ ! -f "$MIHOMO_DIR/bypass-ports.txt" ]; then
  if [ -n "$BYPASS_PORTS" ]; then
    printf '%s\n' "$BYPASS_PORTS" | tr ', ' '\n' | grep -E '^[0-9]{1,5}$' >"$MIHOMO_DIR/bypass-ports.txt" || true
  else
    cp "$TMP/bypass-ports.list" "$MIHOMO_DIR/bypass-ports.txt" || fail "cannot install the bypass list"
  fi
else
  log "keeping the existing $MIHOMO_DIR/bypass-ports.txt"
fi

# The custom list belongs to the user: never overwrite it on a reinstall.
if [ ! -f "$MIHOMO_DIR/lists/custom-domains.list" ]; then
  cp "$TMP/custom-domains.list" "$MIHOMO_DIR/lists/custom-domains.list" || fail "cannot install the custom list"
else
  log "keeping the existing $MIHOMO_DIR/lists/custom-domains.list"
fi

for r in $RULESETS; do
  cp "$TMP/ruleset/$r.mrs" "$MIHOMO_DIR/rule-files/$r.mrs" || fail "cannot install rule-files/$r.mrs"
done
log "$(find "$MIHOMO_DIR/rule-files" -maxdepth 1 -name '*.mrs' | wc -l | tr -d ' ') rule-sets installed"

cp "$TMP/magitrickle.yaml" "$MIHOMO_DIR/magitrickle.yaml" || fail "cannot install the MagiTrickle template"

# --- the state of MagiTrickle -------------------------------------------------
log "building the state configuration of MagiTrickle"
MIHOMO="$CORE" \
RULE_DIR="$MIHOMO_DIR/rule-files" \
CUSTOM_LIST="$MIHOMO_DIR/lists/custom-domains.list" \
TEMPLATE="$MIHOMO_DIR/magitrickle.yaml" \
OUT="$MAGITRICKLE_DIR/state/config.yaml" \
  sh "$MIHOMO_DIR/scripts/gen-mtrickle.sh" || fail "cannot build the MagiTrickle state"

# --- the daily refresh --------------------------------------------------------
setup_cron() {
  if ! command -v crontab >/dev/null 2>&1; then
    log "crontab not found - add the daily job manually (docs/MIXOMO.md)"
    return 0
  fi
  line="30 5 * * * $MIHOMO_DIR/scripts/update-mixomo.sh >/tmp/update-mixomo.log 2>&1"
  ct="$TMP/crontab"
  (crontab -l 2>/dev/null || true) | grep -v 'update-mixomo.sh' >"$ct" || true
  printf '%s\n' "$line" >>"$ct"
  if crontab "$ct" 2>/dev/null; then
    [ -x /etc/init.d/cron ] && { /etc/init.d/cron enable >/dev/null 2>&1 || true; /etc/init.d/cron restart >/dev/null 2>&1 || true; }
    log "cron installed: $line"
  else
    log "cannot write the crontab - add the daily job manually (docs/MIXOMO.md)"
  fi
}

if [ "$ENABLE_CRON" = "1" ]; then
  setup_cron
fi

# --- start --------------------------------------------------------------------
log "starting the services"
/etc/init.d/magitrickle restart >/dev/null 2>&1 || true
/etc/init.d/hev-socks5-tunnel restart >/dev/null 2>&1 || true
/etc/init.d/mihomo restart >/dev/null 2>&1 || true
if [ -x /etc/init.d/mixomo-routing ]; then
  /etc/init.d/mixomo-routing restart >/dev/null 2>&1 || true
fi
sleep 3

# The bypass rule has to stand in front of the chains of MagiTrickle, so it
# is hooked in after the services are up.
if [ -x /etc/init.d/mixomo-bypass ]; then
  /etc/init.d/mixomo-bypass start >/dev/null 2>&1 || true
fi

# --- checks -------------------------------------------------------------------
failures=0
check() { # check <description> <command...>
  if "$@" >/dev/null 2>&1; then
    printf '  OK   %s\n' "$1"
  else
    printf '  FAIL %s\n' "$1"
    failures=$((failures + 1))
  fi
}

if [ "$CHECKS" != "1" ]; then
  log "the checks were skipped (CHECKS=0)"
  exit 0
fi

log "checking the installation"

if "$CORE" -t -f "$MIHOMO_DIR/config.yaml" -d "$MIHOMO_DIR" >/dev/null 2>&1; then
  printf '  OK   the config passes mihomo -t\n'
else
  printf '  FAIL the config does not pass mihomo -t\n'
  failures=$((failures + 1))
fi

for svc in mihomo magitrickle hev-socks5-tunnel; do
  if [ -x "/etc/init.d/$svc" ] && "/etc/init.d/$svc" running >/dev/null 2>&1; then
    printf '  OK   %s is running\n' "$svc"
  else
    printf '  FAIL %s is not running\n' "$svc"
    failures=$((failures + 1))
  fi
done

port_open() { # port_open <port>
  if command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | awk '{print $4}' | grep -q ":$1\$"
  else
    netstat -lnt 2>/dev/null | awk '{print $4}' | grep -q ":$1\$"
  fi
}
for p in 7890 7880; do
  if port_open "$p"; then
    printf '  OK   port %s is listening\n' "$p"
  else
    printf '  FAIL port %s is not listening\n' "$p"
    failures=$((failures + 1))
  fi
done

if ip link show Mihomo >/dev/null 2>&1; then
  printf '  OK   the tunnel device Mihomo exists\n'
else
  printf '  FAIL the tunnel device Mihomo is missing (hev-socks5-tunnel is not running)\n'
  failures=$((failures + 1))
fi

if [ -x /etc/init.d/mixomo-bypass ] && sh "$MIHOMO_DIR/scripts/bypass-ports.sh" status 2>/dev/null | grep -q 'the chain MIXOMO_BYPASS is at position 1'; then
  printf '  OK   the ports bypass the core\n'
elif [ -x /etc/init.d/mixomo-bypass ] && [ ! -s "$MIHOMO_DIR/bypass-ports.txt" ]; then
  printf '  SKIP no ports to bypass (bypass-ports.txt is empty)\n'
else
  printf '  WARN the bypass rule is not in place\n'
fi

if command -v ipset >/dev/null 2>&1 && ipset list -n 2>/dev/null | grep -q '^mt_'; then
  printf '  OK   MagiTrickle has created its address sets\n'
else
  printf '  WARN MagiTrickle has no address sets yet (it fills them after the first DNS answer)\n'
fi

if [ "$failures" -gt 0 ]; then
  log ""
  log "$failures check(s) failed. See docs/MIXOMO.md - section 'Troubleshooting'."
  exit 1
fi

log ""
log "the scheme is installed."
log "  config:      $MIHOMO_DIR/config.yaml"
log "  rule-sets:   $MIHOMO_DIR/rule-files/"
log "  MagiTrickle: $MAGITRICKLE_DIR/state/config.yaml"
log "  interface:   http://192.168.1.1:8080/ (MagiTrickle)"
log "  dashboard:   http://192.168.1.1:9090/ui (mihomo)"
log ""
log "next steps:"
log "  1. Put your own domains into $MIHOMO_DIR/lists/custom-domains.list"
log "     and run: sh $MIHOMO_DIR/scripts/gen-mtrickle.sh"
log "  2. Check the groups: sh $MIHOMO_DIR/scripts/check-groups.sh"
