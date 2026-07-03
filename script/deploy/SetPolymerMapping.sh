#!/bin/bash

# Adds/updates chainId -> CCTP domain mappings on an already-deployed PolymerCCTP diamond
# via setChainIdToDomainId. Owner-only (use the diamond's owner/deployer key).
#
# The target diamond and the domainId for each chainId are read from the config
# (.testnets block), so you only pass the RPC and the chainId(s) to add.

set -eo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
  echo "Usage: $0 <RPC_URL> <PRIVATE_KEY> <CHAIN_ID> [CHAIN_ID...]"
  echo ""
  echo "Arguments:"
  echo "  RPC_URL       RPC of the chain whose diamond you are updating"
  echo "  PRIVATE_KEY   Owner key of that diamond (the deployer)"
  echo "  CHAIN_ID...   One or more chainIds to (re)map; domainId is read from config"
  echo ""
  echo "Env overrides:"
  echo "  CONFIG_FILE       polymercctp config (default: config/polymercctp.json)"
  echo "  DIAMOND_ADDRESS   target diamond (default: .testnets[<currentChainId>].diamondProxy)"
  echo ""
  echo "Example (add rh testnet 46630 to the Base Sepolia diamond):"
  echo "  $0 \"\$BASE_SEPOLIA_RPC\" \"\$PRIVATE_KEY\" 46630"
  exit 1
}

if [ $# -lt 3 ]; then
  echo -e "${RED}Error: Missing required arguments${NC}\n"
  usage
fi

RPC_URL="$1"
PRIVATE_KEY="$2"
shift 2
CHAIN_IDS=("$@")
CONFIG_FILE="${CONFIG_FILE:-config/polymercctp.json}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo -e "${RED}Error: Config file not found: $CONFIG_FILE${NC}"
  exit 1
fi

# Chain we are updating (used to resolve the diamond from config)
CURRENT_CHAIN_ID=$(cast chain-id -r "$RPC_URL")
if [ -z "$CURRENT_CHAIN_ID" ]; then
  echo -e "${RED}Error: Could not fetch chain ID from RPC${NC}"
  exit 1
fi
echo -e "${GREEN}Target chain: $CURRENT_CHAIN_ID${NC}"

# Resolve target diamond: env override, else config .testnets[currentChainId].diamondProxy
if [ -z "$DIAMOND_ADDRESS" ]; then
  DIAMOND_ADDRESS=$(jq -r --arg c "$CURRENT_CHAIN_ID" '.testnets[$c].diamondProxy // empty' "$CONFIG_FILE")
fi
if [ -z "$DIAMOND_ADDRESS" ]; then
  echo -e "${RED}Error: no diamond for chain $CURRENT_CHAIN_ID (set DIAMOND_ADDRESS or add .testnets[$CURRENT_CHAIN_ID].diamondProxy)${NC}"
  exit 1
fi
echo -e "${BLUE}Diamond: $DIAMOND_ADDRESS${NC}"

# Build the ChainIdConfig[] tuple string: [(chainId,domainId),...]
TUPLES="["
for CID in "${CHAIN_IDS[@]}"; do
  DOMAIN=$(jq -r --arg c "$CID" '.testnets[$c].domainId // empty' "$CONFIG_FILE")
  if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: no domainId for chain $CID under .testnets in $CONFIG_FILE${NC}"
    exit 1
  fi
  [ "$TUPLES" != "[" ] && TUPLES+=","
  TUPLES+="($CID,$DOMAIN)"
  echo -e "${BLUE}  mapping $CID -> domain $DOMAIN${NC}"
done
TUPLES+="]"

echo -e "${BLUE}Sending setChainIdToDomainId $TUPLES ...${NC}"
cast send "$DIAMOND_ADDRESS" \
  "setChainIdToDomainId((uint256,uint32)[])" "$TUPLES" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY"

# Verify each mapping landed
echo -e "${BLUE}Verifying...${NC}"
for CID in "${CHAIN_IDS[@]}"; do
  GOT=$(cast call "$DIAMOND_ADDRESS" "getChainIdToDomainId(uint256)(uint32)" "$CID" --rpc-url "$RPC_URL")
  echo -e "${GREEN}  $CID -> $GOT${NC}"
done

echo -e "${GREEN}Done.${NC}"
