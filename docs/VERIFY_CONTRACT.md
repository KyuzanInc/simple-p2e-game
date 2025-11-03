# Contract Verification Guide

This guide explains how to verify deployed contracts on Oasys explorers (powered by Blockscout).

## Prerequisites

```bash
# Required environment variables
RPC_URL               # Network RPC endpoint
EXPLORER_API_URL      # Explorer API endpoint (must end with /api/)
SBT_IMPLEMENTATION    # SoulboundToken implementation address
SBTSALE_IMPLEMENTATION # SBTSale implementation address

# For SBTSale verification (constructor args)
P2E_POAS_MINTER
P2E_LIQUIDITY_POOL
P2E_LP_RECIPIENT
P2E_REVENUE_RECIPIENT
P2E_SMP_BASE_PRICE
P2E_SMP_BURN_RATIO
P2E_SMP_LIQUIDITY_RATIO
```

## Network Endpoints

| Network | Chain ID | RPC URL | Explorer API URL |
|---------|----------|---------|------------------|
| Mainnet | 248 | `https://rpc.mainnet.oasys.games` | `https://explorer.oasys.games/api/` |
| Testnet | 9372 | `https://rpc.testnet.oasys.games` | `https://explorer.testnet.oasys.games/api/` |

## Verify SoulboundToken

```bash
forge verify-contract \
  --rpc-url $RPC_URL \
  --verifier blockscout \
  --verifier-url $EXPLORER_API_URL \
  --watch \
  $SBT_IMPLEMENTATION \
  src/SoulboundToken.sol:SoulboundToken
```

## Verify SBTSale

```bash
# Encode constructor arguments
SBTSALE_CONSTRUCTOR_ARGS=$(cast abi-encode \
  "constructor(address,address,address,address,uint256,uint256,uint256)" \
  $P2E_POAS_MINTER \
  $P2E_LIQUIDITY_POOL \
  $P2E_LP_RECIPIENT \
  $P2E_REVENUE_RECIPIENT \
  $P2E_SMP_BASE_PRICE \
  $P2E_SMP_BURN_RATIO \
  $P2E_SMP_LIQUIDITY_RATIO)

# Verify
forge verify-contract \
  --rpc-url $RPC_URL \
  --verifier blockscout \
  --verifier-url $EXPLORER_API_URL \
  --constructor-args $SBTSALE_CONSTRUCTOR_ARGS \
  --watch \
  $SBTSALE_IMPLEMENTATION \
  src/SBTSale.sol:SBTSale
```

## Get Implementation Address

If you don't have the implementation address:

```bash
IMPLEMENTATION_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc

# For SoulboundToken
SBT_IMPLEMENTATION=$(cast storage $SBT_PROXY $IMPLEMENTATION_SLOT --rpc-url $RPC_URL | sed 's/0x000000000000000000000000/0x/')

# For SBTSale
SBTSALE_IMPLEMENTATION=$(cast storage $SBTSALE_PROXY $IMPLEMENTATION_SLOT --rpc-url $RPC_URL | sed 's/0x000000000000000000000000/0x/')
```
