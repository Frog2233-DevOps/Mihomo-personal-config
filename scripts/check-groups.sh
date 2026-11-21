#!/bin/sh
# =============================================================================
#  check-groups.sh - show what is in every proxy group
# =============================================================================
#  Run it on the router (or from a PC that can reach the API):
#      sh check-groups.sh
#
#  It asks the mihomo API which nodes ended up in which group and warns when
#  a node that must not be used (LTE server, subscription info node) slipped
#  into a group, or when a Russian node ended up in an automatic group.
#
#  Environment variables:
#      API      - address of the mihomo API (default: 127.0.0.1:9090)
#      SECRET   - dashboard password (default: from OPENCLASH secret file)
#
#  Only busybox tools are used, so it runs on OpenWrt as it is.
# =============================================================================

API="${API:-127.0.0.1:9090}"
SECRET="${SECRET:-}"

if [ -z "$SECRET" ] && [ -f /etc/openclash/secret ]; then
  SECRET="$(cat /etc/openclash/secret 2>/dev/null)"
fi

TMP="/tmp/oc_groups.$$.json"
trap 'rm -f "$TMP"' EXIT

if [ -n "$SECRET" ]; then
  curl -s -m 10 -H "Authorization: Bearer $SECRET" "http://$API/proxies" -o "$TMP"
else
  curl -s -m 10 "http://$API/proxies" -o "$TMP"
fi

if [ ! -s "$TMP" ]; then
  echo "ERROR: no answer from http://$API/proxies"
  echo "       Is OpenClash running? Is the dashboard password set?"
  exit 1
fi

# One group per line.
tr ',' '\n' < "$TMP" | sed 's/^{//; s/}$//' > "$TMP.lines"

show() { # show <group name>
  name="$1"
  line="$(grep -F "\"$name\":" "$TMP.lines" | head -n 1)"
  if [ -z "$line" ]; then
    printf '  %-16s NOT FOUND\n' "$name"
    return
  fi
  members="$(printf '%s' "$line" | sed -n 's/.*"all":\[\([^]]*\)\].*/\1/p' \
             | tr ',' '\n' | sed 's/^"//; s/"$//' | grep -v '^$' | wc -l)"
  printf '  %-16s %s node(s)\n' "$name" "$members"
  printf '%s' "$line" | sed -n 's/.*"all":\[\([^]]*\)\].*/\1/p' \
    | tr ',' '\n' | sed 's/^"//; s/"$//' | sed 's/^/      /'
}

echo "=== Proxy groups ==="
for g in "🎯 Final" "🚀 Auto" "⚡ Turbo" "🔁 Failover" "🎯 Manual" \
         "💬 Telegram" "🎮 Discord" "🤖 AI" "▶️ YouTube" "🎬 Streaming" \
         "🐙 GitHub" "📱 Social" "🎮 Steam" "🧱 Roblox" "🕹️ Games" \
         "🌐 CDN" "⭐ Custom" "🚫 RKN Blocked"; do
  show "$g"
done

echo
echo "=== Warnings ==="
bad="$(grep -o '"[^"]*"' "$TMP.lines" \
       | grep -Ei 'LTE|\b4G\b|Mobile|Expiry|Expires|Traffic|Balance|Тариф|Остаток' \
       | sort -u)"
if [ -n "$bad" ]; then
  echo "  These nodes must not be in any group:"
  printf '%s\n' "$bad" | sed 's/^/      /'
else
  echo "  OK: no LTE / info nodes in the groups"
fi

ru_in_auto=0
for g in "🚀 Auto" "⚡ Turbo" "🔁 Failover"; do
  line="$(grep -F "\"$g\":" "$TMP.lines" | head -n 1)"
  if printf '%s' "$line" | grep -qiE '🇷🇺|"RU |Russia'; then
    echo "  WARNING: a Russian node is in the group '$g'"
    ru_in_auto=1
  fi
done
[ "$ru_in_auto" = "0" ] && echo "  OK: no Russian nodes in the automatic groups"
