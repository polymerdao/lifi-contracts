#!/bin/bash

# Exit on error; pipefail so a failed `forge ... | tee` fails the script
# (without it the pipeline returns tee's exit code, masking a reverted tx)
set -eo pipefail

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
  echo "Usage: $0 <RPC_URL> <PRIVATE_KEY> [CONFIG_FILE]"
  echo ""
  echo "Arguments:"
  echo "  RPC_URL              RPC endpoint URL"
  echo "  PRIVATE_KEY          Private key for deployment"
  echo "  CONFIG_FILE          Path to polymercctp testnet config (default: config/polymercctp.testnet.json)"
  echo ""
  echo "The target chain's tokenMessengerV2 / usdc / polymerFeeReceiver / domainId are"
  echo "read from the CONFIG_FILE '.testnets' block, keyed by chainId. The deployed"
  echo "diamondProxy is written back to the same block."
  echo ""
  echo "Example:"
  echo "  $0 https://arb-sepolia.g.alchemy.com/v2/KEY 0xYOURKEY"
  exit 1
}

# Check if we have the required number of arguments
if [ $# -lt 2 ]; then
  echo -e "${RED}Error: Missing required arguments${NC}\n"
  usage
fi

# Parse positional arguments
RPC_URL="$1"
PRIVATE_KEY="$2"
CONFIG_FILE="${3:-config/polymercctp.testnet.json}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo -e "${RED}Error: Config file not found: $CONFIG_FILE${NC}"
  exit 1
fi

# Get chain ID from RPC
echo -e "${BLUE}Fetching chain ID from RPC...${NC}"
CHAIN_ID=$(cast chain-id -r "$RPC_URL")
if [ -z "$CHAIN_ID" ]; then
  echo -e "${RED}Error: Could not fetch chain ID from RPC${NC}"
  exit 1
fi
echo -e "${GREEN}Chain ID: $CHAIN_ID${NC}"

# Ensure the chain is configured in the .testnets block (the forge script reads it via block.chainid)
if [ "$(jq -r --arg c "$CHAIN_ID" '.testnets[$c] // empty' "$CONFIG_FILE")" = "" ]; then
  echo -e "${RED}Error: chain $CHAIN_ID has no entry under .testnets in $CONFIG_FILE${NC}"
  echo "Add it with: usdc, tokenMessengerV2, polymerFeeReceiver, domainId"
  exit 1
fi

# forge reads PRIVATE_KEY from the environment
export PRIVATE_KEY

echo -e "${BLUE}Deploying Diamond with PolymerCCTPFacet to chain $CHAIN_ID...${NC}"

# Create temp file for output
DEPLOY_OUTPUT_FILE=$(mktemp /tmp/forge-deploy-output.XXXXXX)
echo -e "${BLUE}Output will be saved to: $DEPLOY_OUTPUT_FILE${NC}"

# Gas-limit headroom multiplier (percent). forge's local sim does not model the
# L1 data fee on Arbitrum-Orbit L2s (e.g. robinhood), so the default 130% can
# under-provision and the deploy OOGs mid code-deposit. This only raises the
# limit, not the fee paid (you pay for gas used), so a generous value is safe.
GAS_MULTIPLIER="${GAS_ESTIMATE_MULTIPLIER:-300}"

# Deploy. We deliberately do NOT pass --verify here: forge script --verify does not
# supply constructor args, so the immutable-bearing PolymerCCTPFacet never matches the
# on-chain runtime bytecode, and its failing retries would also abort before the config
# write-back. Verification is done explicitly (with --constructor-args) below.
forge script ./script/deploy/facets/DeployDiamondWithPolymerCCTPFacet.s.sol \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --slow \
  --gas-estimate-multiplier "$GAS_MULTIPLIER" \
  2>&1 | tee "$DEPLOY_OUTPUT_FILE"

# Read deployed addresses from the broadcast artifact (source of truth)
BROADCAST_JSON="broadcast/DeployDiamondWithPolymerCCTPFacet.s.sol/$CHAIN_ID/run-latest.json"
if [ ! -f "$BROADCAST_JSON" ]; then
  echo -e "${RED}Error: broadcast artifact not found: $BROADCAST_JSON${NC}"
  exit 1
fi

getDeployedAddress() {
  jq -r --arg n "$1" \
    '.transactions[] | select(.contractName==$n and .transactionType=="CREATE") | .contractAddress' \
    "$BROADCAST_JSON" | head -1
}
DIAMONDCUT_ADDRESS=$(getDeployedAddress DiamondCutFacet)
DIAMOND_ADDRESS=$(getDeployedAddress LiFiDiamond)
FACET_ADDRESS=$(getDeployedAddress PolymerCCTPFacet)

if [ -z "$DIAMOND_ADDRESS" ] || [ "$DIAMOND_ADDRESS" = "null" ]; then
  echo -e "${RED}Error: Could not read LiFiDiamond address from $BROADCAST_JSON${NC}"
  exit 1
fi

echo -e "${GREEN}Diamond deployed at: $DIAMOND_ADDRESS${NC}"

# Write the deployed proxy back into the .testnets block
jq --arg chainId "$CHAIN_ID" \
  --arg address "$DIAMOND_ADDRESS" \
  '.testnets[$chainId].diamondProxy = $address' \
  "$CONFIG_FILE" >"$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

echo -e "${GREEN}Updated $CONFIG_FILE${NC}"

# Verify explicitly on the block explorer. PolymerCCTPFacet's constructor args are
# stored as immutables baked into the runtime bytecode, so the verifier must receive
# --constructor-args to match on-chain code. Verification is best-effort: a failure
# here must not fail an otherwise-successful deploy.
TOKEN_MESSENGER=$(jq -r --arg c "$CHAIN_ID" '.testnets[$c].tokenMessengerV2' "$CONFIG_FILE")
USDC_ADDRESS=$(jq -r --arg c "$CHAIN_ID" '.testnets[$c].usdc' "$CONFIG_FILE")
FEE_RECEIVER=$(jq -r --arg c "$CHAIN_ID" '.testnets[$c].polymerFeeReceiver' "$CONFIG_FILE")
FACET_ARGS=$(cast abi-encode "constructor(address,address,address)" "$TOKEN_MESSENGER" "$USDC_ADDRESS" "$FEE_RECEIVER")

# LiFiDiamond owner is the deployer; read it from the broadcast to avoid the key in argv
DIAMOND_OWNER=$(jq -r '.transactions[] | select(.contractName=="LiFiDiamond") | .arguments[0]' "$BROADCAST_JSON" | head -1)
DIAMOND_ARGS=$(cast abi-encode "constructor(address,address)" "$DIAMOND_OWNER" "$DIAMONDCUT_ADDRESS")

verifyContractOnExplorer() {
  # verifyContractOnExplorer ADDRESS FULLY_QUALIFIED_NAME [ABI_ENCODED_CONSTRUCTOR_ARGS]
  local ADDRESS="$1"
  local FQN="$2"
  local CONSTRUCTOR_ARGS="${3:-}"
  local CMD=(forge verify-contract "$ADDRESS" "$FQN" --chain "$CHAIN_ID" --watch)
  if [ -n "$CONSTRUCTOR_ARGS" ]; then
    CMD+=(--constructor-args "$CONSTRUCTOR_ARGS")
  fi
  echo -e "${BLUE}Verifying $FQN @ $ADDRESS...${NC}"
  if "${CMD[@]}"; then
    echo -e "${GREEN}  verified${NC}"
  else
    echo -e "${RED}  verification failed for $FQN @ $ADDRESS (deploy succeeded; re-run the printed forge verify-contract manually)${NC}"
  fi
}

verifyContractOnExplorer "$DIAMONDCUT_ADDRESS" "src/Facets/DiamondCutFacet.sol:DiamondCutFacet"
verifyContractOnExplorer "$DIAMOND_ADDRESS" "src/LiFiDiamond.sol:LiFiDiamond" "$DIAMOND_ARGS"
verifyContractOnExplorer "$FACET_ADDRESS" "src/Facets/PolymerCCTPFacet.sol:PolymerCCTPFacet" "$FACET_ARGS"

echo -e "${GREEN}Deployment complete!${NC}"
cat <<EOF
To send a test bridge, run:
  PRIVATE_KEY=<deployer-key> DIAMOND_ADDRESS=$DIAMOND_ADDRESS \\
    USDC=\$(jq -r '.testnets["$CHAIN_ID"].usdc' $CONFIG_FILE) DESTINATION_CHAIN_ID=<chainId> \\
    forge script ./script/demoScripts/PolymerCCTP.s.sol --rpc-url "$RPC_URL" --broadcast
EOF
