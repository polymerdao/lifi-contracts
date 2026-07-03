#!/bin/bash
set +e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/DeployPolymerContracts.sh"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <PRIVATE_KEY> [RPC_URL...]"
  echo ""
  echo "RPC URLs can be provided as trailing arguments or via the RPC_URLS env"
  echo "var (newline or space separated). Do NOT hardcode RPC URLs that embed"
  echo "API keys in this file - the pre-commit secret scanner will reject them."
  echo ""
  echo "Per-chain config (addresses + domainId) is read from CONFIG_FILE"
  echo "(default: config/polymercctp.json, override via env)."
  exit 1
fi

PRIVATE_KEY="$1"
shift
CONFIG_FILE="${CONFIG_FILE:-config/polymercctp.json}"

# Remaining positional args are RPC URLs
RPC_LIST=("$@")

# If no positional RPC URLs, fall back to env var
if [ ${#RPC_LIST[@]} -eq 0 ] && [ -n "$RPC_URLS" ]; then
  while IFS= read -r url; do
    [ -n "$url" ] && RPC_LIST+=("$url")
  done <<<"$(echo "$RPC_URLS" | tr ' ' '\n')"
fi

if [ ${#RPC_LIST[@]} -eq 0 ]; then
  echo -e "${RED}Error: No RPC URLs provided (pass as args or set RPC_URLS)${NC}"
  exit 1
fi

FAILED=()

for RPC_URL in "${RPC_LIST[@]}"; do
  echo -e "\n${GREEN}>>> Deploying to: $RPC_URL${NC}"
  if ! "$DEPLOY_SCRIPT" "$RPC_URL" "$PRIVATE_KEY" "$CONFIG_FILE"; then
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
