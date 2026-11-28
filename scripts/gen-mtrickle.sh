#!/usr/bin/env sh
# =============================================================================
#  gen-mtrickle.sh - write the state configuration of MagiTrickle
# =============================================================================
#  MagiTrickle needs the domains of the groups as rules. The subscriptions
#  in the template fetch their lists by themselves, but the local groups
#  (your own domains, Netflix, the AI services, GitHub, Steam) are built
#  from the rule-sets of the core - the same .mrs files the core uses.
#
#  The script writes the state file of the service:
#      /etc/magitrickle/state/config.yaml
#  The old file is kept as .bak, so a failed run never leaves the service
#  without a configuration.
#
#  Usage:
#      sh gen-mtrickle.sh [template] [output]
#
#  Environment variables:
#      MIHOMO        path to the core (default: /usr/bin/mihomo)
#      RULE_DIR      directory with the .mrs files
#                    (default: /etc/mihomo/rule-files)
#      CUSTOM_LIST   your own domains
#                    (default: /etc/mihomo/lists/custom-domains.list)
#      TEMPLATE      the template with the subscriptions
#      OUT           the state file
#
#  The state of the groups - which of them are on - is configurable:
#      GROUP_CUSTOM      the domains of your own list (default: 1 = on)
#      GROUP_STREAMING   Netflix (default: 1 = on)
#      GROUP_AI          OpenAI, Anthropic, xAI (default: 1 = on)
#      GROUP_GITHUB      GitHub (default: 1 = on)
#      GROUP_STEAM       Steam (default: 0 = off)
#
#  The memory of the daemon is the limit of the scheme. The daemon keeps every
#  domain of every list in its RAM, and the router has to hold the daemon,
#  the core and the system at the same time:
#      MAX_DOMAINS    how many domains the daemon may hold (default: 5000,
#                     0 = no limit). A subscription with a bigger list is
#                     switched off, because the oom-killer would take the
#                     daemon and a dead daemon updates nothing.
#                     Measured on a router with 239 MB (MagiTrickle 0.8.2,
#                     daemon 0.5.2-badigit.18): 1 000 domains - 27 MB of
#                     RSS, 5 000 - 79 MB, 10 000 - killed by the oom-killer.
#      PROBE          1 (default) checks the size of the lists before the
#                     state is written; 0 trusts the template. The check
#                     needs the network: a list that cannot be fetched is
#                     left alone.
#      PROBE_TIMEOUT  how long a list may take, in seconds (default: 60)
#
#  The ad list and the IPv6 of MagiTrickle are decided by the router itself:
#      ANTI_AD           auto (default) | 1 | 0
#                        auto: the list is on when the router has at least
#                        MIN_RAM_MB of RAM and the list fits into
#                        MAX_DOMAINS, off otherwise. The list has 110 000
#                        domains, so it is off on the routers with 256 MB.
#                        1: the list is on, even if it does not fit - the
#                        daemon can die of it.
#                        0: the list is off.
#      MIN_RAM_MB        the border for auto (default: 384)
#      IPV6              auto (default) | 1 | 0
#                        auto: MagiTrickle manages IPv6 only when the router
#                        has IPv6 switched on. On a router with IPv6 off the
#                        daemon tries to add an IPv6 route to the tunnel
#                        device and dies (see scripts/mixomo-ipv6.sh).
#
#  POSIX sh (busybox ash on the router), no bash, no python, no jq.
# =============================================================================
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

TEMPLATE="${1:-${TEMPLATE:-$ROOT/magitrickle/magitrickle.yaml}}"
OUT="${2:-${OUT:-/etc/magitrickle/state/config.yaml}}"
MIHOMO="${MIHOMO:-/usr/bin/mihomo}"
RULE_DIR="${RULE_DIR:-/etc/mihomo/rule-files}"
CUSTOM_LIST="${CUSTOM_LIST:-/etc/mihomo/lists/custom-domains.list}"

# The IPv6 of the daemon.
IPV6="${IPV6:-auto}"

# The state of the local groups.
GROUP_CUSTOM="${GROUP_CUSTOM:-1}"
GROUP_STREAMING="${GROUP_STREAMING:-1}"
GROUP_AI="${GROUP_AI:-1}"
GROUP_GITHUB="${GROUP_GITHUB:-1}"
GROUP_STEAM="${GROUP_STEAM:-0}"

# The ad list.
ANTI_AD="${ANTI_AD:-auto}"
MIN_RAM_MB="${MIN_RAM_MB:-384}"

# The memory of the daemon.
MAX_DOMAINS="${MAX_DOMAINS:-5000}"
PROBE="${PROBE:-1}"
PROBE_TIMEOUT="${PROBE_TIMEOUT:-60}"

# The URL of a switched-off subscription. The daemon downloads a list when
# the user asks for an update in the web interface - even when the
# subscription is off. This address fails at once (nothing listens on it),
# so an update of a list that does not fit into the memory of the router
# cannot kill the router.
SAFE_URL="${SAFE_URL:-http://127.0.0.1:1/switched-off.lst}"

log()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

[ -f "$TEMPLATE" ] || fail "template not found: $TEMPLATE"
[ -x "$MIHOMO" ] || fail "core not found: $MIHOMO (set MIHOMO=/path/to/mihomo)"

# A value of the environment is 1 or 0, anything else is a mistake.
on_off() { # on_off <value> <name>
  case "$1" in
    1|0|true|false) ;;
    *) fail "$2 must be 1 or 0 (got: $1)" ;;
  esac
  case "$1" in
    1|true) printf 'true' ;;
    *)      printf 'false' ;;
  esac
}

GROUP_CUSTOM=$(on_off "$GROUP_CUSTOM" GROUP_CUSTOM)
GROUP_STREAMING=$(on_off "$GROUP_STREAMING" GROUP_STREAMING)
GROUP_AI=$(on_off "$GROUP_AI" GROUP_AI)
GROUP_GITHUB=$(on_off "$GROUP_GITHUB" GROUP_GITHUB)
GROUP_STEAM=$(on_off "$GROUP_STEAM" GROUP_STEAM)

case "$MAX_DOMAINS" in
  ''|*[!0-9]*) fail "MAX_DOMAINS must be a number (got: $MAX_DOMAINS)" ;;
esac

WORK="$(mktemp -d /tmp/gen-mtrickle.XXXXXX)" || fail "cannot create a temp directory"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# --- helpers -----------------------------------------------------------------

# The id of a rule: eight hexadecimal characters. MagiTrickle identifies the
# rules by it, and it must stay the same when the list is refreshed, so it is
# derived from the rule itself.
rule_id() {
  if command -v md5sum >/dev/null 2>&1; then
    printf '%s' "$1" | md5sum | cut -c1-8
  else
    printf '%08x' 0
  fi
}

# Domains of a rule-set as plain domain names.
#
# The .mrs files store the rules as "+.example.com" (DOMAIN-SUFFIX). The
# namespace rule of MagiTrickle covers the domain and its subdomains, so
# the prefix is dropped. Everything that is not a plain domain is dropped
# as well - a hyphen is a legal character in a hostname, and dropping it
# would remove domains such as "01-klinika-21.ru" from the list.
mrs_domains() { # mrs_domains <file.mrs> <out>
  [ -f "$1" ] || return 1
  "$MIHOMO" convert-ruleset domain mrs "$1" "$2.raw" >/dev/null 2>&1 || return 1
  sed -e 's/^+[.]//' -e 's/[[:space:]]*$//' "$2.raw" \
    | grep -E '^[A-Za-z0-9_.-]+$' \
    | grep -vE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -u >"$2"
  rm -f "$2.raw"
}

# The same for a plain list of domains (lists/custom-domains.list).
list_domains() { # list_domains <file> <out>
  [ -f "$1" ] || return 1
  sed -e 's/[[:space:]]*$//' -e 's/^+[.]//' "$1" \
    | grep -vE '^[[:space:]]*#' \
    | grep -E '^[A-Za-z0-9_.-]+$' \
    | grep -vE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -u >"$2"
  return 0
}

# One group of the state file.
#
#   group <id> <name> <color> <interface> <enable> <domains file>
#
# An empty list of domains still produces a valid group: MagiTrickle shows
# it in the interface and the user can fill it by hand.
group() {
  printf '  - id: %s\n' "$1"
  printf '    name: "%s"\n' "$2"
  printf '    color: "%s"\n' "$3"
  printf '    interface: %s\n' "$4"
  printf '    enable: %s\n' "$5"
  printf '    rules:\n'
  if [ -f "$6" ] && [ -s "$6" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      printf '      - id: %s\n' "$(rule_id "$d")"
      printf '        name: ""\n'
      printf '        type: namespace\n'
      printf '        rule: "%s"\n' "$d"
      printf '        enable: true\n'
    done <"$6"
  else
    printf '      []\n'
  fi
}

# --- the IPv6 of MagiTrickle --------------------------------------------------
# On a router with IPv6 switched off the daemon has nothing to do with IPv6:
# it would try to add an IPv6 route to the tunnel device and die (the kernel
# refuses it with -EACCES). The daemon is told not to touch IPv6 at all.
ipv6_state() { # ipv6_state -> true | false
  case "$IPV6" in
    1|true)  printf 'false'; return 0 ;;
    0|false) printf 'true'; return 0 ;;
  esac
  if [ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
    v=$(tr -d ' \t\r\n' </proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 0)
    [ "$v" = "1" ] && printf 'true' || printf 'false'
    return 0
  fi
  printf 'false'
}

# --- the ad list --------------------------------------------------------------
# The list has 110 000 domains and the daemon keeps every one of them in its
# memory: about 13 kB per domain (measured on a router with 239 MB of RAM).
# On a router with little RAM the list is switched off, otherwise the
# oom-killer takes the daemon - and with it every other list.
mem_total_mb() {
  [ -r /proc/meminfo ] || return 1
  awk '/^MemTotal:/ { printf "%d", $2 / 1024; exit }' /proc/meminfo
}

anti_ad_state() { # anti_ad_state -> true | false
  case "$ANTI_AD" in
    1|true)  printf 'true'; return 0 ;;
    0|false) printf 'false'; return 0 ;;
  esac
  total=$(mem_total_mb) || { printf 'true'; return 0; }
  if [ "${total:-0}" -ge "$MIN_RAM_MB" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

# --- the size of a list -------------------------------------------------------
# The number of lines of a list. The list is fetched into a temporary file
# and counted; a list that cannot be fetched is reported as "unknown" (the
# empty string) - and a list of an unknown size is switched off, because the
# daemon keeps every domain of a list in its RAM and a list that does not
# fit takes the daemon - and the core with it.
#
# The downloader: mixomo installs curl, but on a plain OpenWrt there is only
# uclient-fetch (busybox) and wget - and this script runs unattended from
# the cron. The same list is in scripts/build-ruleset.sh.
#
# The daemon needs about 13 kB of RAM for every domain of a list (measured:
# 1 000 domains - 27 MB of RSS, 5 000 - 79 MB, 10 000 - killed by the
# oom-killer). MAX_DOMAINS is the limit of the whole state file, so the
# domains of the local groups are counted first and only the rest is left
# for the subscriptions.
count_lines() { # count_lines <url>
  f="$WORK/probe.lst"
  rm -f "$f"
  ok=0
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time "$PROBE_TIMEOUT" -o "$f" "$1" 2>/dev/null && ok=1
  elif command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -q -T "$PROBE_TIMEOUT" -O "$f" "$1" 2>/dev/null && ok=1
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T "$PROBE_TIMEOUT" -O "$f" "$1" 2>/dev/null && ok=1
  fi
  if [ "$ok" != "1" ] || [ ! -s "$f" ]; then
    rm -f "$f"
    printf ''
    return 0
  fi
  n=$(awk 'END { print NR }' "$f")
  rm -f "$f"
  printf '%s' "$n"
}

# --- build the lists ---------------------------------------------------------
log "building the lists of the local groups"

mrs_domains "$RULE_DIR/netflix.mrs" "$WORK/netflix.txt" || : >"$WORK/netflix.txt"
log "  Streaming (netflix.mrs): $(wc -l <"$WORK/netflix.txt" | tr -d ' ') domains"

: >"$WORK/ai.txt"
for m in openai anthropic xai; do
  mrs_domains "$RULE_DIR/$m.mrs" "$WORK/$m.txt" || : >"$WORK/$m.txt"
  cat "$WORK/$m.txt" >>"$WORK/ai.txt" 2>/dev/null || true
done
sort -u "$WORK/ai.txt" >"$WORK/ai.sorted" && mv "$WORK/ai.sorted" "$WORK/ai.txt"
log "  AI (openai+anthropic+xai): $(wc -l <"$WORK/ai.txt" | tr -d ' ') domains"

mrs_domains "$RULE_DIR/github.mrs" "$WORK/github.txt" || : >"$WORK/github.txt"
log "  GitHub (github.mrs): $(wc -l <"$WORK/github.txt" | tr -d ' ') domains"

mrs_domains "$RULE_DIR/steam.mrs" "$WORK/steam.txt" || : >"$WORK/steam.txt"
log "  Steam (steam.mrs): $(wc -l <"$WORK/steam.txt" | tr -d ' ') domains"

if list_domains "$CUSTOM_LIST" "$WORK/custom.txt"; then
  log "  Custom ($CUSTOM_LIST): $(wc -l <"$WORK/custom.txt" | tr -d ' ') domains"
else
  : >"$WORK/custom.txt"
  log "  Custom: no list at $CUSTOM_LIST"
fi

# --- the memory of the daemon -------------------------------------------------
# The daemon holds every domain of every list in its RAM. The limit of the
# whole state file is MAX_DOMAINS; the domains of the local groups are
# counted first, the rest is left for the subscriptions.
group_domains=0
for g in custom netflix ai github steam; do
  case "$g" in
    custom)  on="$GROUP_CUSTOM" ;;
    netflix) on="$GROUP_STREAMING" ;;
    ai)      on="$GROUP_AI" ;;
    github)  on="$GROUP_GITHUB" ;;
    steam)   on="$GROUP_STEAM" ;;
  esac
  [ "$on" = "true" ] || continue
  n=$(awk 'END { print NR }' "$WORK/$g.txt" 2>/dev/null || printf 0)
  group_domains=$((group_domains + n))
done
log "domains of the local groups: $group_domains"

if [ "$MAX_DOMAINS" = "0" ]; then
  budget=0
  log "the limit of the domains is off (MAX_DOMAINS=0)"
else
  budget=$((MAX_DOMAINS - group_domains))
  [ "$budget" -lt 0 ] && budget=0
  log "the limit of the domains: $MAX_DOMAINS, left for the subscriptions: $budget"
fi

# --- write the state file ----------------------------------------------------
# The template holds the app section and the subscriptions. The groups are
# written here, because their rules depend on the lists.
awk '/^groups:[[:space:]]*$/{exit} {print}' "$TEMPLATE" >"$WORK/head.yaml"
awk '/^subscriptions:[[:space:]]*$/{p=1} p' "$TEMPLATE" >"$WORK/subs.yaml"

# The IPv6 of the daemon is decided by the router.
DISABLE_IPV6=$(ipv6_state)
sed -e "s/^\([[:space:]]*\)disableIPv6:.*/\1disableIPv6: $DISABLE_IPV6/" \
  "$WORK/head.yaml" >"$WORK/head2.yaml"
mv "$WORK/head2.yaml" "$WORK/head.yaml"

# --- the subscriptions --------------------------------------------------------
# Every subscription is one list that the daemon downloads and keeps in its
# memory. The records of the template are split up, so that the state of
# every one of them can be decided on its own.
mkdir -p "$WORK/subs"
awk -v dir="$WORK/subs" '
  /^  - id:/ { n++ }
  { if (n == 0) print > (dir "/head.part"); else print > (dir "/sub." n ".part") }
' "$WORK/subs.yaml"

ANTI_AD_STATE=$(anti_ad_state)
subs_count=0
subs_off=0
i=1
while [ -f "$WORK/subs/sub.$i.part" ]; do
  f="$WORK/subs/sub.$i.part"
  i=$((i + 1))
  # The name and the URL are read without a pattern that could stumble over
  # the emojis of the names: the prefix is cut off and the quotes are removed
  # by the shell.
  name=$(sed -n 's/^[[:space:]]*name:[[:space:]]*//p' "$f" | head -1)
  name=${name#\"}
  name=${name%\"}
  url=$(sed -n 's/^[[:space:]]*url:[[:space:]]*//p' "$f" | head -1)
  [ -n "$name" ] || name="(without a name)"
  subs_count=$((subs_count + 1))
  # The state of the list comes from the template. The user decides there -
  # in the web interface of the daemon the decision does not survive the
  # daily run, because this script reads the template, not the current state
  # file.
  state=$(sed -n 's/^[[:space:]]*enable:[[:space:]]*//p' "$f" | head -1 | tr -d '"')
  [ "$state" = "true" ] || [ "$state" = "false" ] || state=true
  why=""

  # The ad list: the state is decided by the amount of RAM of the router.
  # auto: the list is on when the router has enough RAM for it - and when
  # the template switches it on, and when it fits into the budget of the
  # domains like every other list.
  is_anti_ad=no
  if grep -q 'Anti-AD' "$f"; then is_anti_ad=yes; fi
  if [ "$is_anti_ad" = "yes" ]; then
    case "$ANTI_AD" in
      1|true)
        state=true
        ;;
      0|false)
        state=false
        why="the ad list is switched off (ANTI_AD=0)"
        warn "$why"
        ;;
      *)
        if [ "$state" != "true" ]; then
          state=false
        else
          state="$ANTI_AD_STATE"
        fi
        if [ "$state" = "false" ]; then
          why="the ad list is switched off: the router has less than $MIN_RAM_MB MB of RAM"
          warn "$why"
          warn "  (the list has 110 000 domains and the daemon keeps every one of them in its memory)"
          warn "  set ANTI_AD=1 to switch it on anyway"
        fi
        ;;
    esac
  fi

  # The size of the list. A list that does not fit into the memory of the
  # router takes the daemon with it, and a dead daemon updates no list.
  if [ "$state" = "true" ] && [ "$PROBE" = "1" ] && [ -n "$url" ] && [ "$MAX_DOMAINS" != "0" ]; then
    lines=$(count_lines "$url")
    if [ -n "$lines" ]; then
      if [ "$lines" -gt "$budget" ]; then
        state=false
        why="the list has $lines lines, only $budget are left for the subscriptions - it is switched off"
        warn "the list \"$name\" has $lines lines, only $budget are left: it is switched off"
        warn "  (the daemon needs about 13 kB of RAM for every domain; with this list"
        warn "   the oom-killer of the kernel takes the daemon - and the core with it -"
        warn "   and a dead daemon updates no list at all)"
        warn "  raise MAX_DOMAINS, switch a group off (GROUP_*) or use a smaller list"
      else
        log "  $name: $lines lines (the budget is $budget)"
        budget=$((budget - lines))
      fi
    else
      # The size of the list is unknown. The daemon keeps every domain of a
      # list in its RAM: an unknown list is switched off, because the price
      # of a wrong guess is the oom-killer (it takes the daemon and the core
      # with it), and the price of a switched-off list is one list that does
      # not work until it is switched on by hand.
      state=false
      why="the size of the list is unknown - it is switched off"
      warn "the list \"$name\" cannot be fetched - it is switched off (the size of the list is unknown)"
      warn "  (a list that does not fit into the memory of the router takes the daemon with it -"
      warn "   and the core with it - so a list of an unknown size is switched off)"
      warn "  switch it on by hand in the web interface of the daemon, if it is small enough"
    fi
  fi

  if [ "$state" = "false" ]; then
    subs_off=$((subs_off + 1))
  fi
  sed -e "s/^\([[:space:]]*\)enable:[[:space:]]*.*/\1enable: $state/" "$f" >"$f.new"

  # A switched-off subscription must not be able to kill the router. The
  # daemon downloads a list when the user asks for an update in the web
  # interface - even when the subscription is off - and with a big list
  # the oom-killer takes the daemon and the core with it (measured on the
  # router: the update of the list of 81 460 domains killed both).
  # So the URL of a switched-off list points to nothing: the update fails
  # at once, and the original URL stays in the comment of the state file.
  if [ "$state" = "false" ]; then
    awk -v safe="$SAFE_URL" -v why="${why:-the list is switched off}" -v orig="$url" '
      /^[[:space:]]*url:/ {
        printf "    # %s\n", why
        printf "    # the original url: %s\n", orig
        printf "    url: %s\n", safe
        next
      }
      { print }
    ' "$f.new" >"$f.new2"
    mv "$f.new2" "$f.new"
  fi

  mv "$f.new" "$f"
done

# The records are put back together in the order of the template.
: >"$WORK/subs2.yaml"
cat "$WORK/subs/head.part" >>"$WORK/subs2.yaml"
i=1
while [ -f "$WORK/subs/sub.$i.part" ]; do
  cat "$WORK/subs/sub.$i.part" >>"$WORK/subs2.yaml"
  i=$((i + 1))
done
mv "$WORK/subs2.yaml" "$WORK/subs.yaml"

{
  cat "$WORK/head.yaml"
  printf '\ngroups:\n'
  group d9dce3ce "⭐ Custom"       "#ffd700" Mihomo "$GROUP_CUSTOM"    "$WORK/custom.txt"
  group 862d206b "🎬 Streaming"    "#e50914" Mihomo "$GROUP_STREAMING" "$WORK/netflix.txt"
  group 3e61482d "🤖 AI"           "#10a37f" Mihomo "$GROUP_AI"        "$WORK/ai.txt"
  group 89b87e29 "🐙 GitHub"       "#8b949e" Mihomo "$GROUP_GITHUB"    "$WORK/github.txt"
  group c217a8bc "🎮 Steam"        "#66c0f4" Mihomo "$GROUP_STEAM"     "$WORK/steam.txt"
  printf '\n'
  cat "$WORK/subs.yaml"
} >"$WORK/state.yaml"


# The subscriptions must survive: without them the groups would have no
# lists at all.
if ! grep -q '^subscriptions:' "$WORK/state.yaml"; then
  fail "the template has no subscriptions section - $TEMPLATE is broken"
fi

mkdir -p "$(dirname "$OUT")" || fail "cannot create $(dirname "$OUT")"
if [ -f "$OUT" ]; then
  cp "$OUT" "$OUT.bak" || fail "cannot back up $OUT"
fi
cp "$WORK/state.yaml" "$OUT" || fail "cannot write $OUT"
chmod 600 "$OUT" 2>/dev/null || true

log "state configuration written: $OUT ($(wc -c <"$OUT" | tr -d ' ') bytes)"
log "IPv6 of MagiTrickle: disabled=$DISABLE_IPV6"
log "state of the groups: custom=$GROUP_CUSTOM streaming=$GROUP_STREAMING ai=$GROUP_AI github=$GROUP_GITHUB steam=$GROUP_STEAM"
# The state of the ad list after everything: the RAM decides it, and then the
# budget of the domains. The two decisions are not the same.
anti_ad_final=$(awk '
  /^subscriptions:/ { s = 1 }
  s && /name:/ && /Anti-AD/ { found = 1 }
  found && /enable:/ { print $2; exit }
' "$OUT")
log "the ad list (Anti-AD): ${anti_ad_final:-unknown} (the RAM of the router says $ANTI_AD_STATE)"
log "subscriptions: $subs_count in the template, $subs_off switched off"

# --- the same groups in the format of the web interface ------------------------
# The interface exports its groups as JSON with the extension ".mtrickle" and
# imports them back ("Export" / "Import"). The file is written next to the
# state file, so it can be imported into another router or into the interface
# of a router where the script was not run.
MTRICKLE="$OUT.mtrickle"
{
  printf '{"groups":['
  first=1
  for g in custom netflix ai github steam; do
    [ "$first" -eq 1 ] || printf ','
    first=0
    case "$g" in
      custom)  gid=d9dce3ce; gname="⭐ Custom";   gcolor="#ffd700"; gen=true;  genable="$GROUP_CUSTOM" ;;
      netflix) gid=862d206b; gname="🎬 Streaming"; gcolor="#e50914"; gen=true;  genable="$GROUP_STREAMING" ;;
      ai)      gid=3e61482d; gname="🤖 AI";        gcolor="#10a37f"; gen=true;  genable="$GROUP_AI" ;;
      github)  gid=89b87e29; gname="🐙 GitHub";    gcolor="#8b949e"; gen=true;  genable="$GROUP_GITHUB" ;;
      steam)   gid=c217a8bc; gname="🎮 Steam";     gcolor="#66c0f4"; gen=true;  genable="$GROUP_STEAM" ;;
    esac
    printf '{"id":"%s","name":"%s","color":"%s","interface":"Mihomo","enable":%s,"rules":[' \
      "$gid" "$gname" "$gcolor" "$genable"
    if [ "$gen" = true ] && [ -s "$WORK/$g.txt" ]; then
      sep=""
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        printf '%s{"id":"%s","name":"","type":"namespace","rule":"%s","enable":true}' \
          "$sep" "$(rule_id "$d")" "$d"
        sep=","
      done <"$WORK/$g.txt"
    fi
    printf ']}'
  done
  printf ']}\n'
} >"$MTRICKLE" || fail "cannot write $MTRICKLE"

log "groups written for the web interface: $MTRICKLE"
