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

log()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$TEMPLATE" ] || fail "template not found: $TEMPLATE"
[ -x "$MIHOMO" ] || fail "core not found: $MIHOMO (set MIHOMO=/path/to/mihomo)"

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

# --- write the state file ----------------------------------------------------
# The template holds the app section and the subscriptions. The groups are
# written here, because their rules depend on the lists.
awk '/^groups:[[:space:]]*$/{exit} {print}' "$TEMPLATE" >"$WORK/head.yaml"
awk '/^subscriptions:[[:space:]]*$/{p=1} p' "$TEMPLATE" >"$WORK/subs.yaml"

{
  cat "$WORK/head.yaml"
  printf '\ngroups:\n'
  group d9dce3ce "⭐ Custom"       "#ffd700" Mihomo true  "$WORK/custom.txt"
  group 862d206b "🎬 Streaming"    "#e50914" Mihomo true  "$WORK/netflix.txt"
  group 3e61482d "🤖 AI"           "#10a37f" Mihomo true  "$WORK/ai.txt"
  group 89b87e29 "🐙 GitHub"       "#8b949e" Mihomo false "$WORK/github.txt"
  group c217a8bc "🎮 Steam"        "#66c0f4" Mihomo false "$WORK/steam.txt"
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
      custom)  gid=d9dce3ce; gname="⭐ Custom";   gcolor="#ffd700"; gen=true;  genable=true ;;
      netflix) gid=862d206b; gname="🎬 Streaming"; gcolor="#e50914"; gen=true;  genable=true ;;
      ai)      gid=3e61482d; gname="🤖 AI";        gcolor="#10a37f"; gen=true;  genable=true ;;
      github)  gid=89b87e29; gname="🐙 GitHub";    gcolor="#8b949e"; gen=true;  genable=false ;;
      steam)   gid=c217a8bc; gname="🎮 Steam";     gcolor="#66c0f4"; gen=true;  genable=false ;;
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
