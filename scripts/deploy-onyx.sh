#!/usr/bin/env bash
# Deploy Immaculate SDK Agent Builder packages and realm to the Gno.land Onyx testnet (onyx-1).
#
# Usage:
#   GNOKEY_BIN=gnokey bash scripts/deploy-onyx.sh <testnet-key-name> [namespace]
#
# - If [namespace] is omitted, defaults to the deployer key's g1... address
#   (Gno.land allows deploying directly under gno.land/p/<g1addr>/... and gno.land/r/<g1addr>/...
#    without needing a pre-registered vanity username).
# - NEVER embeds any private keys or payout addresses; after deployment, run InitOperator
#   and SetSettlementSink privately from your operator wallet.
set -euo pipefail

KEY_NAME="${1:?Usage: bash scripts/deploy-onyx.sh <testnet-key-name> [namespace]}"
GNOKEY_BIN="${GNOKEY_BIN:-gnokey}"
REMOTE="${GNO_REMOTE:-https://rpc.onyx.testnets.gno.land:443}"
CHAIN_ID="${GNO_CHAIN_ID:-onyx-1}"
GAS_FEE="${GNO_GAS_FEE:-5000000ugnot}"
GAS_WANTED="${GNO_GAS_WANTED:-200000000}"
MAX_DEPOSIT="${GNO_MAX_DEPOSIT:-100000000ugnot}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${2:-}"
if [ -z "$NAMESPACE" ]; then
  NAMESPACE="$("$GNOKEY_BIN" list | awk -v k="$KEY_NAME" '$2 == k || $2 == k"," {for(i=1;i<=NF;i++) if($i ~ /^g1[a-z0-9]+$/) {print $i; exit}}')"
  if [ -z "$NAMESPACE" ]; then
    echo "ERROR: Could not resolve g1 address for key '$KEY_NAME'. Pass [namespace] explicitly." >&2
    exit 2
  fi
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

deploy_pkg() {
  local kind="$1" # p or r
  local name="$2" # signals or assurance
  local src="$REPO/gno.land/$kind/arobi/$name"
  local dst="$STAGE/$kind/$name"
  mkdir -p "$dst"
  cp "$src"/*.gno "$src"/gnomod.toml "$dst/"
  rm -f "$dst"/*_test.gno
  for f in "$dst"/*.gno "$dst"/gnomod.toml; do
    sed -i.bak \
      -e "s|gno.land/p/arobi/|gno.land/p/${NAMESPACE}/|g" \
      -e "s|gno.land/r/arobi/|gno.land/r/${NAMESPACE}/|g" \
      -e "s|/r/arobi/|/r/${NAMESPACE}/|g" \
      "$f"
    rm -f "$f.bak"
  done
  local pkgpath="gno.land/$kind/${NAMESPACE}/$name"
  echo "=== Deploying $pkgpath to $CHAIN_ID ($REMOTE) ==="
  "$GNOKEY_BIN" maketx addpkg \
    --pkgpath "$pkgpath" \
    --pkgdir "$dst" \
    --max-deposit "$MAX_DEPOSIT" \
    --remote "$REMOTE" \
    --chainid "$CHAIN_ID" \
    --gas-fee "$GAS_FEE" \
    --gas-wanted "$GAS_WANTED" \
    --broadcast \
    "$KEY_NAME"
}

deploy_pkg p signals
deploy_pkg p assurance
deploy_pkg r assurance

echo ""
echo "=== Deployed Immaculate SDK Agent Builder to Onyx ($CHAIN_ID) ==="
echo "Explorer: https://onyx.testnets.gno.land/r/${NAMESPACE}/assurance"
echo ""
echo "Next (private operator initialization — never commit payout addresses):"
echo "  $GNOKEY_BIN maketx call --pkgpath gno.land/r/${NAMESPACE}/assurance --func InitOperator --remote $REMOTE --chainid $CHAIN_ID --gas-fee $GAS_FEE --gas-wanted 2000000 --broadcast $KEY_NAME"
echo "  $GNOKEY_BIN maketx call --pkgpath gno.land/r/${NAMESPACE}/assurance --func RunDemoAction --args summarize --args doc:1 --args hello --args 0 --remote $REMOTE --chainid $CHAIN_ID --gas-fee $GAS_FEE --gas-wanted 5000000 --broadcast $KEY_NAME"
