#!/bin/sh
# =============================================================================
#  check-groups.sh - show what is in every proxy group
# =============================================================================
#  Run it on the router (or from a PC that can reach the API):
#      sh check-groups.sh
#
#  It asks the mihomo API which nodes ended up in which group, what every group
#  points to right now ("now:") and warns when a node that must not be used
#  (LTE server, subscription info node) slipped into a group, or when a Russian
#  node ended up in an automatic group.
#
#  Environment variables:
#      API      - address of the mihomo API (default: 127.0.0.1:9090)
#      CONFIG   - the config of the scheme  (default: /etc/mihomo/config.yaml)
#      SECRET   - dashboard password (default: from the config)
#
#  Only busybox tools are used, so it runs on OpenWrt as it is.
# =============================================================================

API="${API:-127.0.0.1:9090}"
CONFIG="${CONFIG:-/etc/mihomo/config.yaml}"
SECRET="${SECRET:-}"

# The secret is in the config of the scheme - the core is started with it.
if [ -z "$SECRET" ] && [ -f "$CONFIG" ]; then
  SECRET="$(sed -n "s/^secret:[ \t]*['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}[ \t]*$/\1/p" "$CONFIG" 2>/dev/null | head -1)"
fi

TMP="/tmp/oc_groups.$$.json"
trap 'rm -f "$TMP"' EXIT

# The downloader. mixomo installs curl, but a plain OpenWrt has only
# uclient-fetch - use whatever is there.
if command -v curl >/dev/null 2>&1; then
  if [ -n "$SECRET" ]; then
    curl -s -m 10 -H "Authorization: Bearer $SECRET" "http://$API/proxies" -o "$TMP"
  else
    curl -s -m 10 "http://$API/proxies" -o "$TMP"
  fi
elif command -v uclient-fetch >/dev/null 2>&1; then
  if [ -n "$SECRET" ]; then
    uclient-fetch -q -T 10 -O "$TMP" --header="Authorization: Bearer $SECRET" "http://$API/proxies"
  else
    uclient-fetch -q -T 10 -O "$TMP" "http://$API/proxies"
  fi
else
  echo "ERROR: neither curl nor uclient-fetch is available"
  exit 1
fi

if [ ! -s "$TMP" ]; then
  echo "ERROR: no answer from http://$API/proxies"
  echo "       Is the core running? Is the dashboard password set?"
  exit 1
fi
# A 401 body is a non-empty answer too. Without this check every group is
# reported as NOT FOUND and the warnings below print a false "OK".
if ! grep -q '"proxies"' "$TMP"; then
  echo "ERROR: the API did not return the proxy list: $(head -c 160 "$TMP")"
  echo "       Check the API address and the dashboard password (SECRET)."
  exit 1
fi

# The members of one group. The API returns the fields of a proxy in
# alphabetical order, so the array "all" comes right after the name.
members_of() { # members_of <group name>
  sed -n "s/.*\"$1\":{[^[]*\"all\":\[\([^]]*\)\].*/\1/p" "$TMP" | head -1 \
    | tr ',' '\n' | sed 's/^"//; s/"$//' | grep -v '^$'
}

# What a group points to right now. The automatic groups have it as well
# (the node they picked), so this shows what the config really does.
#
# The JSON of a group is an object with nested objects ("extra"), so a plain
# sed cannot cut it off. This awk walks the string and counts the braces:
# the group ends where its depth returns to zero.
now_of() { # now_of <group name>
  awk -v want="$1" '
    BEGIN { RS = "\0" }
    {
      s = $0
      gsub(/\n/, "", s)
      key = "\"" want "\":{"
      start = index(s, key)
      if (start == 0) exit
      i = start + length(key) - 1
      depth = 1; inq = 0; out = ""
      while (i <= length(s)) {
        c = substr(s, i, 1)
        if (inq) {
          out = out c
          if (c == "\\") { i++; out = out substr(s, i, 1) }
          else if (c == "\"") inq = 0
          i++
          continue
        }
        if (c == "\"") { inq = 1; out = out c; i++; continue }
        if (c == "{") depth++
        else if (c == "}") { depth--; if (depth == 0) break }
        out = out c
        i++
      }
      if (match(out, /"now":"[^"]*"/)) print substr(out, RSTART + 7, RLENGTH - 8)
    }
  ' "$TMP"
}

show() { # show <group name>
  name="$1"
  members="$(members_of "$name")"
  if [ -z "$members" ]; then
    printf '  %-16s NOT FOUND\n' "$name"
    return
  fi
  count="$(printf '%s\n' "$members" | grep -c .)"
  now="$(now_of "$name")"
  if [ -n "$now" ]; then
    printf '  %-16s %s node(s)   now: %s\n' "$name" "$count" "$now"
  else
    printf '  %-16s %s node(s)\n' "$name" "$count"
  fi
  printf '%s\n' "$members" | sed 's/^/      /'
}

echo "=== Proxy groups ==="
# The groups are read out of the config of the scheme, so a new group in it is
# shown without touching this script. The built-in list is the fallback.
groups_of_config() {
  [ -f "$CONFIG" ] || return 1
  awk '
    /^proxy-groups:/ { p = 1; next }
    p && /^[^[:space:]]/ { p = 0 }
    p && /^[[:space:]]*-[[:space:]]*name:/ {
      n = $0
      sub(/^[^:]*:[[:space:]]*/, "", n)
      gsub(/^["'"'"']|["'"'"']$/, "", n)
      print n
    }
  ' "$CONFIG"
}

# The list of the groups. The name of the variable is not GROUPS: that is a
# builtin of the shell (the list of the gids of the user), and assigning a
# string to it breaks the shell.
GROUP_LIST="$(groups_of_config)"
if [ -z "$GROUP_LIST" ]; then
  GROUP_LIST="🎯 Final
🚀 Auto
⚡ Turbo
🔁 Failover
🎯 Manual
💬 Telegram
🎮 Discord
🤖 AI
▶️ YouTube
🎬 Streaming
🐙 GitHub
📱 Social
🎮 Steam
🧱 Roblox
🕹️ Games
🌐 CDN
⭐ Custom
🚫 RKN Blocked"
fi

printf '%s\n' "$GROUP_LIST" | while IFS= read -r g; do
  [ -n "$g" ] || continue
  show "$g"
done

echo
echo "=== Warnings ==="

# Every member of every group.
all_members() {
  grep -o '"all":\[[^]]*\]' "$TMP" | sed 's/"all":\[//; s/\]//' \
    | tr ',' '\n' | sed 's/^"//; s/"$//' | grep -v '^$'
}

# \b is a GNU extension and busybox grep does not know it - spell the word
# boundaries out.
bad="$(all_members | grep -Ei 'LTE|(^|[^0-9A-Za-z])4G([^0-9A-Za-z]|$)|Mobile|MTS|Beeline|MegaFon|Tele2|Expiry|Expires|Traffic|Balance|Тариф|Остаток' | sort -u)"
if [ -n "$bad" ]; then
  echo "  These nodes must not be in any group:"
  printf '%s\n' "$bad" | sed 's/^/      /'
else
  echo "  OK: no LTE / info nodes in the groups"
fi

ru_warning=0
for g in "🚀 Auto" "⚡ Turbo" "🔁 Failover"; do
  if members_of "$g" | grep -qiE '🇷🇺|^RU |Russia|Москва'; then
    echo "  WARNING: a Russian node is in the group '$g'"
    ru_warning=1
  fi
done
[ "$ru_warning" = "0" ] && echo "  OK: no Russian nodes in the automatic groups"
