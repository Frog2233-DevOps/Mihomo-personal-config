#!/usr/bin/env bash
# =============================================================================
#  deploy.sh - copy the config and the rule-sets to the router
# =============================================================================
#  Usage:
#      ROUTER_HOST=192.168.1.1 ROUTER_USER=root ./scripts/deploy.sh
#
#  Environment variables:
#      ROUTER_HOST     - address of the router          (required)
#      ROUTER_USER     - ssh user                       (default: root)
#      ROUTER_PORT     - ssh port                       (default: 22)
#      ROUTER_PATH     - where the config lives         (default: /etc/openclash)
#      CONFIG          - which config to deploy         (default: RU-Mihomo.yaml)
#      RESTART         - "1" to restart OpenClash after the copy (default: 0)
#      SSH_KEY         - private key file               (default: ~/.ssh/id_ed25519)
#
#  On GitHub Actions the values come from the repository secrets:
#      ROUTER_HOST, ROUTER_USER, ROUTER_PATH, SSH_PRIVATE_KEY
#  See .github/workflows/rulesets.yml.
#
#  The subscription URL is NOT deployed from here: OpenClash substitutes it
#  from its own settings (RU-Mihomo.conf, SUB_INFO_URL).
# =============================================================================
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

ROUTER_HOST="${ROUTER_HOST:-}"
ROUTER_USER="${ROUTER_USER:-root}"
ROUTER_PORT="${ROUTER_PORT:-22}"
ROUTER_PATH="${ROUTER_PATH:-/etc/openclash}"
CONFIG="${CONFIG:-RU-Mihomo.yaml}"
RESTART="${RESTART:-0}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

[ -n "$ROUTER_HOST" ] || { echo "ERROR: set ROUTER_HOST"; exit 1; }
[ -f "$ROOT/$CONFIG" ] || { echo "ERROR: $ROOT/$CONFIG not found"; exit 1; }

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -p $ROUTER_PORT"
[ -f "$SSH_KEY" ] && SSH_OPTS="$SSH_OPTS -i $SSH_KEY"

echo "=== Deploying $CONFIG to $ROUTER_USER@$ROUTER_HOST:$ROUTER_PATH ==="

echo "--- config ---"
scp $SSH_OPTS "$ROOT/$CONFIG" "$ROUTER_USER@$ROUTER_HOST:$ROUTER_PATH/config/$CONFIG"

echo "--- rulesets ---"
scp $SSH_OPTS "$ROOT"/ruleset/*.mrs "$ROUTER_USER@$ROUTER_HOST:$ROUTER_PATH/ruleset/"

echo "--- scripts (for the automatic rule-set update on the router) ---"
scp $SSH_OPTS "$ROOT"/scripts/build-ruleset.sh "$ROOT"/scripts/update-rulesets.sh \
    "$ROUTER_USER@$ROUTER_HOST:$ROUTER_PATH/"
ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" "chmod +x $ROUTER_PATH/build-ruleset.sh $ROUTER_PATH/update-rulesets.sh"

echo "--- openclash settings ---"
scp $SSH_OPTS "$ROOT/RU-Mihomo.conf" "$ROUTER_USER@$ROUTER_HOST:$ROUTER_PATH/backup/RU-Mihomo.conf"

if [ "$RESTART" = "1" ]; then
  echo "--- restarting OpenClash ---"
  ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" "/etc/init.d/openclash restart"
fi

echo "Done. Check the result with:"
echo "  ssh $ROUTER_USER@$ROUTER_HOST '/etc/openclash/check-groups.sh'"
