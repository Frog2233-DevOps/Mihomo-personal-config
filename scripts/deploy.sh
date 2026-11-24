#!/usr/bin/env bash
# =============================================================================
#  deploy.sh - copy the config and the rule-sets to the router
# =============================================================================
#
#  Usage:
#      ROUTER_HOST=192.168.1.1 ROUTER_USER=root ./scripts/deploy.sh
#
#  Environment variables:
#      ROUTER_HOST     - address of the router          (required)
#      ROUTER_USER     - ssh user                       (default: root)
#      ROUTER_PORT     - ssh port                       (default: 22)
#      ROUTER_PATH     - where the config lives         (default: /etc/openclash)
#      CONFIG          - which config to deploy         (default: RU-Mihomo.yaml)
#      APPLY           - reload | restart | none        (default: reload)
#      SSH_KEY         - private key file               (default: ~/.ssh/id_ed25519)
#
#  On GitHub Actions the values come from the repository secrets:
#      ROUTER_HOST, ROUTER_USER, ROUTER_PATH, SSH_PRIVATE_KEY
#  See .github/workflows/rulesets.yml.
#
#  The subscription URL is NOT deployed from here: OpenClash substitutes it
#  from its own settings (RU-Mihomo.conf, SUB_INFO_URL).
#
#  Two details that cost an evening if you do not know them:
#
#    scp -O   OpenSSH 8.9+ copies over SFTP by default. The dropbear of
#             OpenWrt has no sftp-server, so the copy fails with
#             "subsystem request failed". -O forces the old SCP protocol.
#             The flag is used only if the local scp knows it.
#
#    layout   The scripts take the repository root from their own location
#             (the folder above scripts/), so on the router they keep the
#             layout of the repository:
#                 $ROUTER_PATH/scripts/   build-ruleset.sh, update-rulesets.sh,
#                                        apply-rulesets.sh
#                 $ROUTER_PATH/lists/     custom-domains.list
#                 $ROUTER_PATH/ruleset/   the .mrs files
#             Copied flat into $ROUTER_PATH the root becomes /etc and the
#             build stops with "lists/custom-domains.list not found".
# =============================================================================
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

ROUTER_HOST="${ROUTER_HOST:-}"
ROUTER_USER="${ROUTER_USER:-root}"
ROUTER_PORT="${ROUTER_PORT:-22}"
ROUTER_PATH="${ROUTER_PATH:-/etc/openclash}"
CONFIG="${CONFIG:-RU-Mihomo.yaml}"
APPLY="${APPLY:-reload}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

[ -n "$ROUTER_HOST" ] || { echo "ERROR: set ROUTER_HOST"; exit 1; }
[ -f "$ROOT/$CONFIG" ] || { echo "ERROR: $ROOT/$CONFIG not found"; exit 1; }

SSH_COMMON="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
SSH_OPTS="$SSH_COMMON -p $ROUTER_PORT"
# scp uses -P for the port (-p means "preserve times" there). Sharing the
# ssh option string breaks every deploy with a non-default ROUTER_PORT.
SCP_OPTS_PORT="$SSH_COMMON -P $ROUTER_PORT"
[ -f "$SSH_KEY" ] && SSH_OPTS="$SSH_OPTS -i $SSH_KEY" && SCP_OPTS_PORT="$SCP_OPTS_PORT -i $SSH_KEY"

# OpenSSH 9+ copies over SFTP by default; dropbear on OpenWrt has no
# sftp-server. -O forces the old SCP protocol where the flag exists. Older
# clients do not know it, so try with -O first and fall back automatically.
do_scp() {
  err="$(scp $SCP_OPTS_PORT -O "$@" 2>&1)" && return 0
  scp $SCP_OPTS_PORT "$@" || { printf '%s\n' "$err" >&2; return 1; }
}

echo "=== Deploying $CONFIG to $ROUTER_USER@$ROUTER_HOST:$ROUTER_PATH ==="

echo "--- folders on the router ---"
ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" \
  "mkdir -p '$ROUTER_PATH/config' '$ROUTER_PATH/ruleset' '$ROUTER_PATH/backup' \
        '$ROUTER_PATH/scripts' '$ROUTER_PATH/lists'"

echo "--- config ---"
do_scp "$ROOT/$CONFIG" "$ROUTER_USER@$ROUTER_HOST:$ROUTER_PATH/config/$CONFIG"

echo "--- rulesets ---"
do_scp "$ROOT"/ruleset/*.mrs "$ROUTER_USER@$ROUTER_HOST:$ROUTER_PATH/ruleset/"

echo "--- scripts (for the automatic rule-set update on the router) ---"
do_scp "$ROOT"/scripts/build-ruleset.sh "$ROOT"/scripts/update-rulesets.sh \
    "$ROOT"/scripts/apply-rulesets.sh "$ROOT"/scripts/check-groups.sh \
    "$ROUTER_USER@$ROUTER_HOST:$ROUTER_PATH/scripts/"

echo "--- lists ---"
do_scp "$ROOT"/lists/*.list "$ROUTER_USER@$ROUTER_HOST:$ROUTER_PATH/lists/"

echo "--- openclash settings ---"
do_scp "$ROOT/RU-Mihomo.conf" "$ROUTER_USER@$ROUTER_HOST:$ROUTER_PATH/backup/RU-Mihomo.conf"

echo "--- preparing the scripts on the router ---"
# A checkout from Windows can bring CRLF with it - busybox ash stops at the
# first carriage return. Strip them, they are never needed here.
ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" \
  "sed -i 's/\r\$//' '$ROUTER_PATH'/scripts/*.sh '$ROUTER_PATH'/lists/*.list 2>/dev/null; \
   chmod +x '$ROUTER_PATH'/scripts/*.sh"

if [ "$APPLY" = "none" ]; then
  echo "--- APPLY=none - the new rule-sets are used after the next restart of OpenClash ---"
else
  echo "--- applying (APPLY=$APPLY) ---"
  ssh $SSH_OPTS "$ROUTER_USER@$ROUTER_HOST" "APPLY='$APPLY' sh '$ROUTER_PATH/scripts/apply-rulesets.sh'"
fi

echo "Done. Check the result with:"
echo "  ssh $ROUTER_USER@$ROUTER_HOST 'sh $ROUTER_PATH/scripts/check-groups.sh'"
