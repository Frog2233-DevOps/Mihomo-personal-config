#!/usr/bin/env bash
# =============================================================================
#  build-ruleset.sh - generate the mrs rule files for RU-Mihomo
# =============================================================================
#  Why this is needed:
#    The RKN lists (refilter) contain bare domains ("instagram.com").
#    In mihomo a bare domain with behavior: domain matches ONLY that exact
#    domain - "www.instagram.com" slips through. Measured, not assumed.
#    So every bare entry gets the "+." prefix (-> DOMAIN-SUFFIX) before the
#    conversion to mrs, and subdomains match as well.
#
#  Requires: mihomo (for convert-ruleset) and network access.
#  Usage:     ./build-ruleset.sh [output_dir]
# =============================================================================
set -u

OUT="${1:-./ruleset}"
MIHOMO="${MIHOMO:-mihomo}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$OUT"

log()  { printf '  %-26s %s\n' "$1" "$2"; }
step() { printf '\n=== %s ===\n' "$1"; }

fetch() { # fetch <url> <dest>
  curl -fsSL --retry 3 --retry-delay 2 "$1" -o "$2" 2>/dev/null
}

# --- 1. Download the source lists --------------------------------------------
step "1. Downloading source lists"

fetch "https://github.com/1andrevich/Re-filter-lists/releases/latest/download/domains_all.lst" "$WORK/rkn.lst"
log "domains_all.lst" "$(wc -l < "$WORK/rkn.lst" 2>/dev/null || echo MISSING) lines"

fetch "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/community.lst" "$WORK/community.lst"
log "community.lst" "$(wc -l < "$WORK/community.lst" 2>/dev/null || echo MISSING) lines"

fetch "https://github.com/1andrevich/Re-filter-lists/releases/latest/download/ipsum.lst" "$WORK/rkn-ip.lst"
log "ipsum.lst" "$(wc -l < "$WORK/rkn-ip.lst" 2>/dev/null || echo MISSING) lines"

fetch "https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-domains.txt" "$WORK/antiad.txt"
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
      # drop junk lines
      if (line !~ /^[A-Za-z0-9_.]+$/) { next }
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

# --- 4. Copy the ready-made mrs files from MetaCubeX --------------------------
step "4. Downloading ready-made mrs files from MetaCubeX"

mc() { # mc <category> <file>
  fetch "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/$1/$2.mrs" "$OUT/$2.mrs"
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
mc geoip   private

fetch "https://raw.githubusercontent.com/HenryChiao/mihomo_yamls/refs/heads/ruleset/meta/domain/fake-ip-filter.mrs" "$OUT/fake-ip-filter.mrs"
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
