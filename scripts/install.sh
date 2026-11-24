#!/usr/bin/env sh
# =============================================================================
#  install.sh - one-command installation of RU-Mihomo on an OpenWrt router
# =============================================================================
#  Run on the router, after OpenClash is installed (see docs/INSTALL.md):
#
#      curl -fsSL -o /tmp/install.sh \
#        https://raw.githubusercontent.com/Frog2233-DevOps/Mihomo-personal-config/main/scripts/install.sh
#      SUB_URL='https://provider/subscribe' DASHBOARD_PASSWORD='your-password' \
#        sh /tmp/install.sh
#
#  Read /tmp/install.sh before running it - it comes from the network.
#
#  Environment variables:
#      SUB_URL            required - the subscription URL
#      DASHBOARD_PASSWORD required - the mihomo API / dashboard secret
#      VARIANT            full (default), lite or smart
#      BRANCH             main (default) or dev
#      REPO               owner/repo, for forks
#      ROOT               router config root (default: /etc/openclash)
#      BASE_URL           override the download root (for local testing)
#      ENABLE_CRON        install the daily router cron (default: on for
#                         /etc/openclash, off for a custom ROOT); 0 disables it
#
#  What it does: downloads the config, the overwrite file, the scripts, the
#  custom list and all 28 compiled rule-sets into the OpenClash layout,
#  substitutes the two placeholders, verifies the result and prints what to
#  do next. Nothing is changed until every file has been downloaded.
# =============================================================================
set -eu

ROOT="${ROOT:-/etc/openclash}"
REPO="${REPO:-Frog2233-DevOps/Mihomo-personal-config}"
BRANCH="${BRANCH:-main}"
VARIANT="${VARIANT:-full}"
SUB_URL="${SUB_URL:-}"
DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD:-}"
BASE_URL="${BASE_URL:-}"
ENABLE_CRON="${ENABLE_CRON:-}"
if [ -z "$ENABLE_CRON" ]; then
  if [ "$ROOT" = "/etc/openclash" ]; then ENABLE_CRON=1; else ENABLE_CRON=0; fi
fi

# Keep in sync with ruleset/ - tests/07_install.sh checks this list against
# the repository, so a new rule-set cannot be forgotten here.
RULESETS="anthropic anti-ad apple category-ai-ru category-games category-ru cdn
custom-domains discord facebook fake-ip-filter github google-gemini instagram
microsoft netflix openai private rkn-blocked-ip rkn-blocked rkn-community roblox
ru steam telegram twitter xai youtube"

log()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -n "$SUB_URL" ] || fail "set SUB_URL to your subscription URL"
[ -n "$DASHBOARD_PASSWORD" ] || fail "set DASHBOARD_PASSWORD (it must not be empty)"
case "$VARIANT" in
  full)  CFG=RU-Mihomo.yaml ;;
  lite)  CFG=RU-Mihomo-lite.yaml ;;
  smart) CFG=RU-Mihomo-smart.yaml ;;
  *)     fail "VARIANT must be full, lite or smart (got: $VARIANT)" ;;
esac
# Root is only required for the system path. A custom ROOT (tests, another
# user's config directory) works with normal permissions.
if [ "$ROOT" = "/etc/openclash" ] && [ "$(id -u)" != "0" ]; then
  fail "run as root (or set ROOT to a directory you own)"
fi

# --- downloader ------------------------------------------------------------
DL=""
for c in curl uclient-fetch wget; do
  if command -v "$c" >/dev/null 2>&1; then DL="$c"; break; fi
done
[ -n "$DL" ] || fail "no curl, uclient-fetch or wget found"

if [ -n "$BASE_URL" ]; then
  BASES="$BASE_URL"
else
  # The direct link first, then the mirrors, as in build-ruleset.sh.
  BASES="https://raw.githubusercontent.com/$REPO/$BRANCH https://cdn.jsdelivr.net/gh/$REPO@$BRANCH https://gh-proxy.com/https://raw.githubusercontent.com/$REPO/$BRANCH"
fi

fetch_one() { # fetch_one <url> <dest>
  case "$DL" in
    curl)          curl -fsSL --retry 1 --connect-timeout 15 --max-time 120 "$1" -o "$2" ;;
    uclient-fetch) uclient-fetch -q -T 15 -O "$2" "$1" ;;
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

# sed replacement with the three characters that break a | delimited expression
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# --- download everything into a temporary directory first ------------------
TMP="$(mktemp -d /tmp/ru-mihomo-install.XXXXXX)" || fail "cannot create a temp directory"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/ruleset" "$TMP/scripts" "$TMP/lists"

log "downloading $CFG from $REPO@$BRANCH"
fetch "$CFG" "$TMP/config.yaml" || fail "cannot download $CFG"
fetch "RU-Mihomo.conf" "$TMP/overwrite.conf" || fail "cannot download RU-Mihomo.conf"

for s in build-ruleset.sh update-rulesets.sh apply-rulesets.sh check-groups.sh; do
  fetch "scripts/$s" "$TMP/scripts/$s" || fail "cannot download scripts/$s"
done
fetch "lists/custom-domains.list" "$TMP/lists/custom-domains.list" || fail "cannot download the custom list"

n=0
for r in $RULESETS; do
  fetch "ruleset/$r.mrs" "$TMP/ruleset/$r.mrs" || fail "cannot download ruleset/$r.mrs"
  n=$((n + 1))
done
[ "$n" -eq 28 ] || fail "internal error: expected 28 rule-sets, got $n"

# --- substitute the placeholders in the downloaded copies ------------------
# The secret and the URL are never printed, only written into the files.
sed -i "s|PASTE_SUBSCRIPTION_URL_HERE|$(esc "$SUB_URL")|g;
        s|CHANGE_ME|$(esc "$DASHBOARD_PASSWORD")|g" \
  "$TMP/config.yaml" "$TMP/overwrite.conf"

# --- install ----------------------------------------------------------------
mkdir -p "$ROOT/config" "$ROOT/ruleset" "$ROOT/backup" "$ROOT/scripts" "$ROOT/lists"

set_target() { # set_target <source> <destination>
  if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
    cp "$2" "$2.bak" || fail "cannot back up $2"
  fi
  cp "$1" "$2" || fail "cannot install $2"
}

set_target "$TMP/config.yaml"     "$ROOT/config/$CFG"
set_target "$TMP/overwrite.conf"  "$ROOT/backup/RU-Mihomo.conf"
set_target "$TMP/overwrite.conf"  "$ROOT/RU-Mihomo.conf"

for s in build-ruleset.sh update-rulesets.sh apply-rulesets.sh check-groups.sh; do
  set_target "$TMP/scripts/$s" "$ROOT/scripts/$s"
  chmod +x "$ROOT/scripts/$s" || fail "cannot chmod $ROOT/scripts/$s"
done

# The custom list belongs to the user: never overwrite it on a reinstall.
if [ ! -f "$ROOT/lists/custom-domains.list" ]; then
  cp "$TMP/lists/custom-domains.list" "$ROOT/lists/custom-domains.list" || fail "cannot install the custom list"
else
  log "keeping the existing $ROOT/lists/custom-domains.list"
fi

for r in $RULESETS; do
  cp "$TMP/ruleset/$r.mrs" "$ROOT/ruleset/$r.mrs" || fail "cannot install ruleset/$r.mrs"
done

# --- the router refreshes the lists itself ----------------------------------
# OpenWrt has no /etc/cron.d: the job goes into root's crontab. Keep OpenClash's
# own entries and never add the same line twice.
setup_cron() {
  if ! command -v crontab >/dev/null 2>&1; then
    log "crontab not found - add the daily rule-set job manually (docs/INSTALL.md)"
    return 0
  fi
  line="30 5 * * * $ROOT/scripts/update-rulesets.sh >/tmp/update-rulesets.log 2>&1"
  ct="$TMP/crontab"
  (crontab -l 2>/dev/null || true) | grep -v 'update-rulesets.sh' >"$ct" || true
  printf '%s\n' "$line" >>"$ct"
  if crontab "$ct" 2>/dev/null; then
    if [ -x /etc/init.d/cron ]; then
      /etc/init.d/cron enable >/dev/null 2>&1 || true
      /etc/init.d/cron restart >/dev/null 2>&1 || true
    fi
    log "cron installed: $line"
  else
    log "cannot write the crontab - add the daily job manually (docs/INSTALL.md)"
  fi
}

if [ "$ENABLE_CRON" = "1" ]; then
  setup_cron
fi

# --- verify -----------------------------------------------------------------
installed=0
for f in "$ROOT"/ruleset/*.mrs; do
  [ -f "$f" ] || continue
  [ -s "$f" ] || fail "empty rule-set: $f"
  installed=$((installed + 1))
done
[ "$installed" -ge 28 ] || fail "only $installed rule-sets installed"
if grep -q 'PASTE_SUBSCRIPTION_URL_HERE\|CHANGE_ME' "$ROOT/config/$CFG" "$ROOT/backup/RU-Mihomo.conf"; then
  fail "a placeholder was left in the installed files"
fi

CORE=""
for c in "$ROOT/core/mihomo" "$ROOT/clash" "$ROOT/core/clash_meta"; do
  [ -n "$CORE" ] && break
  [ -x "$c" ] && CORE="$c"
done
[ -n "$CORE" ] || CORE="$(command -v mihomo 2>/dev/null || true)"
if [ -n "$CORE" ] && [ -x "$CORE" ]; then
  if "$CORE" -t -f "$ROOT/config/$CFG" -d "$ROOT" >/dev/null 2>&1; then
    log "config validated with $CORE"
  else
    fail "mihomo -t rejected the installed config"
  fi
else
  log "no core found yet - mihomo -t skipped until OpenClash is started"
fi

log "installed $CFG + $installed rule-sets into $ROOT"
if [ "$ENABLE_CRON" = "1" ]; then
  log "the router will rebuild the lists daily at 05:00 (cron)"
else
  log "cron was not installed - ENABLE_CRON=1 enables it (docs/INSTALL.md)"
fi
log "next steps:"
log "  1. In LuCI: OpenClash -> Config Manage -> Config Subscribe, import"
log "     $ROOT/backup/RU-Mihomo.conf (or pick it in the overwrite settings)."
log "  2. /etc/init.d/openclash restart"
log "  3. sh $ROOT/scripts/check-groups.sh"
