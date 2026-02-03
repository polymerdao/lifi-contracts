#!/bin/bash

usage() {
  echo "Usage: $0 <INFRA_REPO_PATH> <ENVIRONMENT> <PRIVATE_KEY> <ADDRESS_FILE>"
  echo ""
  echo "Arguments:"
  echo "  INFRA_REPO_PATH - Path to the infrastructure repository"
  echo "  ENVIRONMENT     - Environment name (e.g., testnet, mainnet)"
  echo "  PRIVATE_KEY     - Private key for deployment"
  echo "  ADDRESS_FILE    - Path to the addresses JSON file"
  echo ""
  echo "Example:"
  echo "  $0 ~/Code/infra testnet 0x... ./testnet-addresses.json"
  exit 1
}

# Validate required arguments
if [ $# -ne 4 ]; then
  echo "Error: Incorrect number of arguments"
  echo ""
  usage
fi

# Parse arguments
INFRA_REPO_PATH="$1"
ENVIRONMENT="$2"
PRIVATE_KEY="$3"
ADDRESS_FILE="$4"

# Configuration
CHAIN_NAMES=(
  "hyperevm"
  "monad"
  "linea"
  "ink"
  "plume"
  "sonic"
  "worldchain"
)


DEPLOYER_ADDR=$(cast wallet address $PRIVATE_KEY)
TARGET_ADDR=0x765D1689B1B2556236fa201d1dd731CD1365fcd4
# Deploy to each chain
for CHAIN_NAME in "${CHAIN_NAMES[@]}"; do
  echo "Deploying to $CHAIN_NAME..."

  # Extract RPC URL from infra repo
  RPC_PATH="$INFRA_REPO_PATH/overlays/$ENVIRONMENT/rpcx/routes/$CHAIN_NAME.yaml"
  
  echo using rpc path: $RPC_PATH
  YQ_QUERY=.routes./"$CHAIN_NAME".upstreams[0].url
  echo using yq query: $YQ_QUERY 

  RPC=$(yq "$YQ_QUERY" "$RPC_PATH")

  if [ -z "$RPC" ]; then
    echo "Error: Could not find RPC URL for $CHAIN_NAME"
    continue
  fi

  echo Using RPC: $RPC
  CHAIN_ID=$(cast chain-id -r $RPC)
  echo $CHAIN_NAME CHAIN ID: $CHAIN_ID

  # Check if chain ID exists in address file
  if ! jq -e ".[\"$CHAIN_ID\"]" "$ADDRESS_FILE" > /dev/null 2>&1; then
    echo "Chain ID $CHAIN_ID not found in $ADDRESS_FILE, adding template..."

    # Create template and append to address file
    jq ". + {\"$CHAIN_ID\": {\"name\": \"$CHAIN_NAME\", \"usdc\": \"\", \"polymerFeeRecipient\": \"0x356DC9e113a006d5e85556A54DCA865832dAC06B\", \"tokenMessenger\": \"0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d\", \"diamondProxy\": \"\"}}" "$ADDRESS_FILE" > "$ADDRESS_FILE.tmp" && mv "$ADDRESS_FILE.tmp" "$ADDRESS_FILE"

    echo "Template added for chain ID $CHAIN_ID"
  else
    echo "Chain ID $CHAIN_ID already exists in $ADDRESS_FILE"
  fi

  # BALANCE=$(cast balance $DEPLOYER_ADDR -r $RPC -e)
  # BALANCE_1=$(cast balance $TARGET_ADDR -r $RPC -e)
  # AMOUNT=$(printf "%.5f" $(echo "$BALANCE * 0.95" | bc))
  # echo balance for $DEPLOYER_ADDR: $BALANCE
  # echo balance for $TARGET_ADDR: $BALANCE_1

  # cast send $TARGET_ADDR --value "$AMOUNT"ether  -r $RPC --private-key $PRIVATE_KEY
  ./script/deploy/DeployPolymerContracts.sh "$RPC" "$PRIVATE_KEY" "$ADDRESS_FILE"

done