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
#      SECRET   - dashboard password (default: from /etc/openclash/secret)
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

# OpenClash installs curl as a dependency, but a plain OpenWrt has only
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
  echo "       Is OpenClash running? Is the dashboard password set?"
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

show() { # show <group name>
  name="$1"
  members="$(members_of "$name")"
  if [ -z "$members" ]; then
    printf '  %-16s NOT FOUND\n' "$name"
    return
  fi
  count="$(printf '%s\n' "$members" | grep -c .)"
  printf '  %-16s %s node(s)\n' "$name" "$count"
  printf '%s\n' "$members" | sed 's/^/      /'
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
