#!/bin/bash
set +e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/DeployPolymerContracts.sh"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <PRIVATE_KEY> <ADDRESSES_FILE> [RPC_URL...]"
  echo ""
  echo "RPC URLs can also be provided via RPC_URLS env var (newline or space separated)."
  exit 1
fi

PRIVATE_KEY="$1"
ADDRESSES_FILE="$2"

RPC_LIST=(
  #  'https://radial-spring-replica.base-sepolia.quiknode.pro/0f7ad8a891e66d4fff9e4948167bc649f82b627b/'
  'https://summer-damp-wish.optimism-sepolia.quiknode.pro/275a0c449ec6250e331b32756dbfe88cf7d3fa2c/'
  'https://icy-proportionate-lake.ethereum-sepolia.quiknode.pro/26849d593dd1c4c50f44f9afa531c650d119c65f/'
  'https://restless-warmhearted-feather.arbitrum-sepolia.quiknode.pro/40c1cffbfe0d6f55fa91d9a74ae6d9b51286bd2e/'
  'https://avax-fuji.g.alchemy.com/v2/rWQSfPx_ffDzY73wEPziIzFDcNCYZ7PE'
  'https://lb.drpc.org/ogrpc?network=polygon-amoy&dkey=AmCu45CoVUk4iYSPPhOlrSd5MfT3ZkoR75uuyp-Zw4Id'
  'https://unichain-sepolia.g.alchemy.com/v2/rWQSfPx_ffDzY73wEPziIzFDcNCYZ7PE'
  'https://lb.drpc.live/hyperliquid-testnet/AmCu45CoVUk4iYSPPhOlrSd5MfT3ZkoR75uuyp-Zw4Id'
  'https://lb.drpc.org/ogrpc?network=linea-sepolia&dkey=AmCu45CoVUk4iYSPPhOlrSd5MfT3ZkoR75uuyp-Zw4Id'
  'https://distinguished-young-asphalt.ink-sepolia.quiknode.pro/4035517cd76d7838fdd9664e157b056d7309c8de/'
  'https://testnet-rpc.plume.org'
  'https://lb.drpc.org/ogrpc?network=sonic-testnet&dkey=AmCu45CoVUk4iYSPPhOlrSd5MfT3ZkoR75uuyp-Zw4Id'
  'https://lb.drpc.org/ogrpc?network=worldchain-sepolia&dkey=AmCu45CoVUk4iYSPPhOlrSd5MfT3ZkoR75uuyp-Zw4Id'
  'https://testnet-rpc.monad.xyz'
)

# If no positional RPC URLs, fall back to env var
if [ ${#RPC_LIST[@]} -eq 0 ] && [ -n "$RPC_URLS" ]; then
  while IFS= read -r url; do
    [ -n "$url" ] && RPC_LIST+=("$url")
  done <<<"$(echo "$RPC_URLS" | tr ' ' '\n')"
fi

if [ ${#RPC_LIST[@]} -eq 0 ]; then
  echo -e "${RED}Error: No RPC URLs provided${NC}"
  exit 1
fi

FAILED=()

for RPC_URL in "${RPC_LIST[@]}"; do
  echo -e "\n${GREEN}>>> Deploying to: $RPC_URL${NC}"
  if ! "$DEPLOY_SCRIPT" "$RPC_URL" "$PRIVATE_KEY" "$ADDRESSES_FILE"; then
    echo -e "${RED}>>> FAILED: $RPC_URL${NC}"
    FAILED+=("$RPC_URL")
  fi
done

echo ""
if [ ${#FAILED[@]} -gt 0 ]; then
  echo -e "${RED}Failed deployments (${#FAILED[@]}):${NC}"
  for url in "${FAILED[@]}"; do
    echo "  - $url"
  done
  exit 1
else
  echo -e "${GREEN}All ${#RPC_LIST[@]} deployments succeeded.${NC}"
fi
