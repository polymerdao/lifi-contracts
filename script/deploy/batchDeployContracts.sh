#!/bin/bash

usage() {
  echo "Usage: $0 <INFRA_REPO_PATH> <ENVIRONMENT> <PRIVATE_KEY>"
  echo ""
  echo "Arguments:"
  echo "  INFRA_REPO_PATH - Path to the infrastructure repository"
  echo "  ENVIRONMENT     - Environment name (e.g., testnet, mainnet)"
  echo "  PRIVATE_KEY     - Private key for deployment"
  echo ""
  echo "Example:"
  echo "  $0 ~/Code/infra testnet 0x..."
  exit 1
}

# Validate required arguments
if [ $# -ne 3 ]; then
  echo "Error: Incorrect number of arguments"
  echo ""
  usage
fi

# Parse arguments
INFRA_REPO_PATH="$1"
ENVIRONMENT="$2"
PRIVATE_KEY="$3"

# Configuration
CHAIN_NAMES=(
  # "hyperevm"
  "monad"
  "linea"
  # "ink"
  "plume"
  "sonic"
  "worldchain"
)


DEPLOYER_ADDR=$(cast wallet address $PRIVATE_KEY)
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
  # echo $CHAIN_NAME CHAIN ID: $(cast chain-id -r $RPC)

  # BALANCE=$(cast balance $DEPLOYER_ADDR -r $RPC -e)
  # echo balance for $DEPLOYER_ADDR: $BALANCE

  ./script/deploy/DeployPolymerContracts.sh "$RPC" "$PRIVATE_KEY" ./testnet-addresses.json


done