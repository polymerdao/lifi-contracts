PRIVATE_KEY=$(cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-derivation-path "m/44'/60'/0'/0/0/0")
export PRIVATE_KEY=$PRIVATE_KEY

export USDC=0x036CbD53842c5426634e7929541eC2318f3dCF7e
export DIAMOND_ADDRESS=0x4a0258A6627e9D8cef54B52Bde9814B13570Cbb7
export AMOUNT=1000
export DESTINATION_DOMAIN=5
export MIN_FINALITY_THRESHOLD=2000

forge script script/demoScripts/PolymerCCTP.s.sol --rpc-url https://radial-spring-replica.base-sepolia.quiknode.pro/0f7ad8a891e66d4fff9e4948167bc649f82b627b/ --broadcast
