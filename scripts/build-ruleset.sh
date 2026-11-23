#!/bin/sh
# =============================================================================
#  build-ruleset.sh - build the .mrs rule files for RU-Mihomo
# =============================================================================
#  Why this script and not plain downloads:
#    The RKN lists (refilter) contain bare domains ("instagram.com"). In
#    mihomo a bare domain with behavior: domain matches ONLY that exact
#    domain - "www.instagram.com" slips through. Measured, not assumed.
#    So every bare entry gets the "+." prefix (-> DOMAIN-SUFFIX) before the
#    conversion to mrs, and subdomains match as well.
#
#  It also builds the rule-set from lists/custom-domains.list and fetches the
#  ready-made mrs files from MetaCubeX.
#
#  Requires: mihomo (for convert-ruleset) and network access.
#  Usage:     ./scripts/build-ruleset.sh [output_dir]
#
#  Run it from the repository root, or with an explicit output directory:
#      ./scripts/build-ruleset.sh ./ruleset
#
#  On a router without internet access to GitHub, run it on a PC and copy the
#  ruleset/ folder over (scripts/deploy.sh does that).
# =============================================================================
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
OUT="${1:-$ROOT/ruleset}"
CUSTOM_LIST="${CUSTOM_LIST:-$ROOT/lists/custom-domains.list}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Find the core: the PATH first, then the repository root (the CI downloads it
# there). The script must not depend on being executable itself.
MIHOMO="${MIHOMO:-}"
if [ -z "$MIHOMO" ]; then
  if command -v mihomo >/dev/null 2>&1; then
    MIHOMO="$(command -v mihomo)"
  elif [ -x "$ROOT/mihomo" ]; then
    MIHOMO="$ROOT/mihomo"
  else
    echo "ERROR: mihomo not found. Put it in the PATH or in the repository root,"
    echo "       or set MIHOMO=/path/to/mihomo."
    exit 1
  fi
fi

mkdir -p "$OUT"

log()  { printf '  %-26s %s\n' "$1" "$2"; }
step() { printf '\n=== %s ===\n' "$1"; }

# The direct link first, then the mirrors. From a router in Russia
# raw.githubusercontent.com is not always fast, and sometimes blocked.
# fetch <dest> <url> [url ...]
fetch() {
  dest="$1"; shift
  for u in "$@"; do
    if curl -fsSL --retry 2 --retry-delay 2 --connect-timeout 15 "$u" -o "$dest" 2>/dev/null \
       && [ -s "$dest" ]; then
      return 0
    fi
  done
  rm -f "$dest"
  return 1
}

# --- 1. Download the source lists --------------------------------------------
step "1. Downloading source lists"

fetch "$WORK/rkn.lst" \
  "https://github.com/1andrevich/Re-filter-lists/releases/latest/download/domains_all.lst" \
  "https://ghfast.top/https://github.com/1andrevich/Re-filter-lists/releases/latest/download/domains_all.lst" \
  "https://gh-proxy.com/https://github.com/1andrevich/Re-filter-lists/releases/latest/download/domains_all.lst"
log "domains_all.lst" "$(wc -l < "$WORK/rkn.lst" 2>/dev/null || echo MISSING) lines"

fetch "$WORK/community.lst" \
  "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/community.lst" \
  "https://cdn.jsdelivr.net/gh/1andrevich/Re-filter-lists@main/community.lst" \
  "https://gh-proxy.com/https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/community.lst"
log "community.lst" "$(wc -l < "$WORK/community.lst" 2>/dev/null || echo MISSING) lines"

fetch "$WORK/rkn-ip.lst" \
  "https://github.com/1andrevich/Re-filter-lists/releases/latest/download/ipsum.lst" \
  "https://ghfast.top/https://github.com/1andrevich/Re-filter-lists/releases/latest/download/ipsum.lst" \
  "https://gh-proxy.com/https://github.com/1andrevich/Re-filter-lists/releases/latest/download/ipsum.lst"
log "ipsum.lst" "$(wc -l < "$WORK/rkn-ip.lst" 2>/dev/null || echo MISSING) lines"

fetch "$WORK/antiad.txt" \
  "https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-domains.txt" \
  "https://cdn.jsdelivr.net/gh/privacy-protection-tools/anti-AD@master/anti-ad-domains.txt" \
  "https://gh-proxy.com/https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-domains.txt"
log "anti-ad-domains.txt" "$(wc -l < "$WORK/antiad.txt" 2>/dev/null || echo MISSING) lines"

for f in rkn community antiad; do
  [ -s "$WORK/$f.lst" ] || [ -s "$WORK/$f.txt" ] || { echo "ERROR: $f not downloaded"; exit 1; }
done

# --- 2. Normalise domains to DOMAIN-SUFFIX ------------------------------------
step "2. Normalising domains (adding the '+.' prefix)"

normalize() { # normalize <in> <out>
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      sub(/\r$/, "")
      line = $0
      # already prefixed entries stay as they are
      if (line ~ /^\+\./) { print line; next }
      if (line ~ /^\*\./) { print "+." substr(line, 3); next }
      # Drop non-domain lines (adblock syntax, URLs, spaces, ...).
      # A hyphen is a legal character in a hostname label (and in punycode,
      # e.g. xn--...), so it must stay in the class: dropping it silently
      # removes domains such as "01-klinika-21.ru" from the RKN list.
      if (line !~ /^[A-Za-z0-9_.-]+$/) { next }
      # IP-like strings do not belong in a domain file
      if (line ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) { next }
      print "+." line
    }
    ' "$1" | sort -u > "$2"
}

normalize "$WORK/rkn.lst"       "$WORK/rkn.norm"
normalize "$WORK/community.lst" "$WORK/community.norm"
normalize "$WORK/antiad.txt"    "$WORK/antiad.norm"
log "rkn (after normalisation)"      "$(wc -l < "$WORK/rkn.norm")"
log "community (after normalisation)" "$(wc -l < "$WORK/community.norm")"
log "antiad (after normalisation)"    "$(wc -l < "$WORK/antiad.norm")"

# Your own list
if [ -f "$CUSTOM_LIST" ]; then
  normalize "$CUSTOM_LIST" "$WORK/custom.norm"
  log "custom-domains.list" "$(wc -l < "$WORK/custom.norm") domains"
  if [ ! -s "$WORK/custom.norm" ]; then
    # mihomo panics with "empty rule" on an empty list and leaves a 0 byte
    # file behind, which the core then fails to load. Use a reserved domain
    # that can never resolve (RFC 2606) so the rule-set stays valid.
    echo "DOMAIN-SUFFIX,custom-domains.invalid" > "$WORK/custom.norm"
    echo "  NOTE: $CUSTOM_LIST is empty - a placeholder rule is used."
  fi
else
  echo "ERROR: $CUSTOM_LIST not found"
  exit 1
fi

# --- 3. Convert to mrs --------------------------------------------------------
step "3. Converting to mrs (behavior: domain / ipcidr)"

convert() { # convert <behavior> <src> <dst>
  "$MIHOMO" convert-ruleset "$1" text "$2" "$3" 2>/dev/null
  if [ -s "$3" ]; then
    log "$(basename "$3")" "$(du -h "$3" | cut -f1) (from $(du -h "$2" | cut -f1))"
  else
    log "$(basename "$3")" "CONVERSION ERROR"
    return 1
  fi
}

convert domain  "$WORK/rkn.norm"       "$OUT/rkn-blocked.mrs"     || exit 1
convert domain  "$WORK/community.norm" "$OUT/rkn-community.mrs"   || exit 1
convert domain  "$WORK/antiad.norm"    "$OUT/anti-ad.mrs"        || exit 1
convert ipcidr  "$WORK/rkn-ip.lst"     "$OUT/rkn-blocked-ip.mrs" || exit 1
convert domain  "$WORK/custom.norm"    "$OUT/custom-domains.mrs" || exit 1

# --- 4. Copy the ready-made mrs files from MetaCubeX --------------------------
step "4. Downloading ready-made mrs files from MetaCubeX"

mc() { # mc <category> <file>
  fetch "$OUT/$2.mrs" \
    "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/$1/$2.mrs" \
    "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/$1/$2.mrs" \
    "https://gh-proxy.com/https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/$1/$2.mrs" \
    "https://ghproxy.net/https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/$1/$2.mrs"
  if [ -s "$OUT/$2.mrs" ]; then log "$2.mrs" "$(du -h "$OUT/$2.mrs" | cut -f1)"
  else log "$2.mrs" "ERROR"; rm -f "$OUT/$2.mrs"; fi
}

mc geosite category-ru
mc geoip   ru
mc geosite telegram
mc geosite discord
mc geosite instagram
mc geosite facebook
mc geosite twitter
mc geosite youtube
mc geosite netflix
mc geosite github
mc geosite microsoft
mc geosite apple
mc geosite category-games
mc geosite steam
mc geosite roblox
mc geosite category-ai-ru
mc geosite openai
mc geosite anthropic
mc geosite google-gemini
mc geosite xai
# CDN of the big providers, without the Chinese ones.
mc geosite 'category-cdn-!cn'
mv "$OUT/category-cdn-!cn.mrs" "$OUT/cdn.mrs" 2>/dev/null
log "cdn.mrs" "$(du -h "$OUT/cdn.mrs" 2>/dev/null | cut -f1)"
mc geoip   private

fetch "$OUT/fake-ip-filter.mrs" \
  "https://raw.githubusercontent.com/HenryChiao/mihomo_yamls/refs/heads/ruleset/meta/domain/fake-ip-filter.mrs" \
  "https://cdn.jsdelivr.net/gh/HenryChiao/mihomo_yamls@ruleset/meta/domain/fake-ip-filter.mrs" \
  "https://gh-proxy.com/https://raw.githubusercontent.com/HenryChiao/mihomo_yamls/refs/heads/ruleset/meta/domain/fake-ip-filter.mrs"
log "fake-ip-filter.mrs" "$(du -h "$OUT/fake-ip-filter.mrs" 2>/dev/null | cut -f1)"

# --- 5. Result -----------------------------------------------------------------
step "5. Result"
total=0
for f in "$OUT"/*.mrs; do
  sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
  total=$((total + sz))
done
printf '  Files: %s, total: %s\n' "$(ls -1 "$OUT"/*.mrs 2>/dev/null | wc -l)" "$(du -sh "$OUT" | cut -f1)"
printf '  Bytes: %s\n\n' "$total"
echo "Done. Files in: $OUT"
