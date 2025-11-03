# SBTSale Upgrade Guide

This guide explains how to upgrade the SBTSale implementation contract.

## Overview

SBTSale uses OpenZeppelin's TransparentUpgradeableProxy pattern with three components:

1. **Implementation**: The SBTSale contract logic
2. **Proxy**: Delegates calls to the implementation
3. **ProxyAdmin**: Contract that manages proxy upgrades

The ProxyAdmin is automatically deployed when you deploy the proxy. The address you specify as `P2E_ADMIN` becomes the **owner of the ProxyAdmin contract**.

## Prerequisites

```bash
# Required environment variables in .envrc.mainnet or .envrc.testnet
SBTSALE_PROXY            # The proxy address
SBTSALE_PROXY_ADMIN      # The ProxyAdmin contract address
P2E_ADMIN                # The ProxyAdmin owner (your address)

# Constructor parameters (must match original deployment)
P2E_POAS_MINTER
P2E_LIQUIDITY_POOL
P2E_LP_RECIPIENT
P2E_REVENUE_RECIPIENT
P2E_SMP_BASE_PRICE
P2E_SMP_BURN_RATIO
P2E_SMP_LIQUIDITY_RATIO
```

## Step 1: Get ProxyAdmin Address

If you don't have `SBTSALE_PROXY_ADMIN` set, retrieve it:

```bash
ADMIN_SLOT=0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
SBTSALE_PROXY_ADMIN=$(cast storage $SBTSALE_PROXY $ADMIN_SLOT --rpc-url $RPC_URL | sed 's/0x000000000000000000000000/0x/')
echo "ProxyAdmin: $SBTSALE_PROXY_ADMIN"
```

Add this to your `.envrc.mainnet` or `.envrc.testnet` and reload:

```bash
export SBTSALE_PROXY_ADMIN="0x..."
direnv allow
```

## Step 2: Deploy New Implementation

### Testnet

```bash
forge create \
  src/SBTSale.sol:SBTSale \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY \
  --constructor-args \
    $P2E_POAS_MINTER \
    $P2E_LIQUIDITY_POOL \
    $P2E_LP_RECIPIENT \
    $P2E_REVENUE_RECIPIENT \
    $P2E_SMP_BASE_PRICE \
    $P2E_SMP_BURN_RATIO \
    $P2E_SMP_LIQUIDITY_RATIO
```

### Mainnet (Fireblocks)

```bash
FIREBLOCKS_API_KEY=$FIREBLOCKS_API_KEY \
FIREBLOCKS_API_PRIVATE_KEY_PATH=$FIREBLOCKS_API_PRIVATE_KEY_PATH \
FIREBLOCKS_CHAIN_ID=$FIREBLOCKS_CHAIN_ID \
fireblocks-json-rpc --http -- \
forge create src/SBTSale.sol:SBTSale \
  --from $DEPLOYER_ADDRESS \
  --unlocked \
  --broadcast \
  --constructor-args \
    $P2E_POAS_MINTER \
    $P2E_LIQUIDITY_POOL \
    $P2E_LP_RECIPIENT \
    $P2E_REVENUE_RECIPIENT \
    $P2E_SMP_BASE_PRICE \
    $P2E_SMP_BURN_RATIO \
    $P2E_SMP_LIQUIDITY_RATIO \
  --rpc-url {}
```

Save the deployed address:

```bash
export SBTSALE_IMPLEMENTATION="0x..."
```

## Step 3: Upgrade the Proxy

Upgrades are performed through the ProxyAdmin contract using `upgradeAndCall()`.

### Testnet

```bash
cast send $SBTSALE_PROXY_ADMIN \
  "upgradeAndCall(address,address,bytes)" \
  $SBTSALE_PROXY \
  $SBTSALE_IMPLEMENTATION \
  "0x" \
  --rpc-url $RPC_URL \
  --from $P2E_ADMIN \
  --private-key $PRIVATE_KEY
```

### Mainnet (Fireblocks)

```bash
FIREBLOCKS_API_KEY=$FIREBLOCKS_API_KEY \
FIREBLOCKS_API_PRIVATE_KEY_PATH=$FIREBLOCKS_API_PRIVATE_KEY_PATH \
FIREBLOCKS_CHAIN_ID=$FIREBLOCKS_CHAIN_ID \
fireblocks-json-rpc --http -- \
cast send $SBTSALE_PROXY_ADMIN \
  "upgradeAndCall(address,address,bytes)" \
  $SBTSALE_PROXY \
  $SBTSALE_IMPLEMENTATION \
  "0x" \
  --from $P2E_ADMIN \
  --unlocked \
  --rpc-url {} \
  --slow
```

## Step 4: Verify

```bash
# Check the new implementation address
IMPLEMENTATION_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
cast storage $SBTSALE_PROXY $IMPLEMENTATION_SLOT --rpc-url $RPC_URL

# Verify state is preserved
cast call $SBTSALE_PROXY "owner()(address)" --rpc-url $RPC_URL
cast call $SBTSALE_PROXY "getSigner()(address)" --rpc-url $RPC_URL
```

## Rollback

To revert to a previous implementation:

```bash
# Set the old implementation address
OLD_IMPLEMENTATION="0x..."

# Run the upgrade command again with the old address
cast send $SBTSALE_PROXY_ADMIN \
  "upgradeAndCall(address,address,bytes)" \
  $SBTSALE_PROXY \
  $OLD_IMPLEMENTATION \
  "0x" \
  --rpc-url $RPC_URL \
  --from $P2E_ADMIN \
  --private-key $PRIVATE_KEY
```
