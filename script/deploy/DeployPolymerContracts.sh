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
  echo "  CONFIG_FILE          Path to polymercctp config (default: config/polymercctp.json)"
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
CONFIG_FILE="${3:-config/polymercctp.json}"

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

# Run deployment script and save output to temp file
forge script ./script/deploy/facets/DeployDiamondWithPolymerCCTPFacet.s.sol \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --verify \
  --slow \
  --gas-estimate-multiplier "$GAS_MULTIPLIER" \
  2>&1 | tee "$DEPLOY_OUTPUT_FILE"

DEPLOY_OUTPUT=$(cat "$DEPLOY_OUTPUT_FILE")

# Extract diamond address from output
DIAMOND_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "LiFiDiamond deployed at: " | awk '{print $4}')

if [ -z "$DIAMOND_ADDRESS" ]; then
  echo -e "${RED}Error: Could not extract diamond address from deployment output${NC}"
  exit 1
fi

echo -e "${GREEN}Diamond deployed at: $DIAMOND_ADDRESS${NC}"

# Write the deployed proxy back into the .testnets block
jq --arg chainId "$CHAIN_ID" \
  --arg address "$DIAMOND_ADDRESS" \
  '.testnets[$chainId].diamondProxy = $address' \
  "$CONFIG_FILE" >"$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

echo -e "${GREEN}Updated $CONFIG_FILE${NC}"
echo -e "${GREEN}Deployment complete!${NC}"
cat <<EOF
To send a test bridge, run:
  PRIVATE_KEY=<deployer-key> DIAMOND_ADDRESS=$DIAMOND_ADDRESS \\
    USDC=\$(jq -r '.testnets["$CHAIN_ID"].usdc' $CONFIG_FILE) DESTINATION_CHAIN_ID=<chainId> \\
    forge script ./script/demoScripts/PolymerCCTP.s.sol --rpc-url "$RPC_URL" --broadcast
EOF
