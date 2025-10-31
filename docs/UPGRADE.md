# SBTSale Upgrade Guide

This document covers how to roll out SBTSale implementation upgrades on the Oasys Testnet and Mainnet. SBTSale is deployed behind a `TransparentUpgradeableProxy`, so upgrades consist of deploying a new implementation contract and instructing the proxy admin to point to it.

## Prerequisites

- Foundry toolchain installed (`forge`, `cast`)
- Environment configured via `.envrc.testnet` or `.envrc.mainnet`
- Proxy admin private key (testnet) or Fireblocks vault (mainnet) with permission to call `upgradeTo`
- Updated `.envrc.*` values for:
  - `$SBTSALE_PROXY`
  - `$P2E_ADMIN`
  - Constructor parameters (`$P2E_POAS_MINTER`, `$P2E_LIQUIDITY_POOL`, `$P2E_LP_RECIPIENT`, `$P2E_REVENUE_RECIPIENT`, `$P2E_SMP_BASE_PRICE`, `$P2E_SMP_BURN_RATIO`, `$P2E_SMP_LIQUIDITY_RATIO`)
- Optional: `$SBTSALE_IMPLEMENTATION` pointing at the current implementation (helps with rollback validation)

## Prepare Environment

1. Switch to the desired network:
   ```bash
   npm run env:switch:testnet   # or env:switch:mainnet
   ```
2. Verify the expected variables are loaded:
   ```bash
   npm run env:status
   env | grep -E "^(RPC_URL|EXPLORER_API_URL|SBTSALE_|P2E_)"
   ```
3. Confirm that the deployer credentials are available:

   ```bash
   # Testnet: must print the same address as $P2E_ADMIN
   cast wallet address --private-key $PRIVATE_KEY

   # Mainnet: must print the Fireblocks vault account defined in $DEPLOYER_ADDRESS
   echo $DEPLOYER_ADDRESS
   ```

## Deploy the New Implementation

### Testnet (Private Key Deployment)

Deploy a fresh SBTSale implementation using the existing constructor parameters:

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

> `forge create` defaults to a dry run; the `--broadcast` flag is required to submit the transaction. If a dry-run warning still appears, ensure no shell profile sets `FOUNDRY_BROADCAST=0` or `FOUNDRY_DRY_RUN=1`.

Record the implementation address printed by `forge create` and update `.envrc.testnet`:

```bash
export SBTSALE_IMPLEMENTATION="0xNEW_IMPLEMENTATION"
```

### Mainnet (Fireblocks Deployment)

Deploy via the Fireblocks JSON-RPC bridge. The deployer address must match your Fireblocks vault account (`$DEPLOYER_ADDRESS`):

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

> Fireblocks will stage the transaction for policy approval. Ensure the JSON-RPC server runs with broadcasting enabled and that the vault account has deployment permissions.

After deployment, write the new address to `.envrc.mainnet`:

```bash
export SBTSALE_IMPLEMENTATION="0xNEW_IMPLEMENTATION"
```

Reload the environment (`direnv allow` or `npm run env:switch:*`) so subsequent commands pick up the new value.

## Upgrade the Proxy

### Testnet (Private Key Admin)

Ensure `$PRIVATE_KEY` corresponds to `$P2E_ADMIN`. Then execute:

```bash
cast send $SBTSALE_PROXY \
  "upgradeTo(address)" \
  $SBTSALE_IMPLEMENTATION \
  --rpc-url $RPC_URL \
  --from $P2E_ADMIN \
  --private-key $PRIVATE_KEY
```

> `cast send` broadcasts immediately. Double-check the target address and arguments before executing.

### Mainnet (Fireblocks Admin)

Use the same Fireblocks credentials and admin address (`$P2E_ADMIN`) to trigger the upgrade:

```bash
FIREBLOCKS_API_KEY=$FIREBLOCKS_API_KEY \
FIREBLOCKS_API_PRIVATE_KEY_PATH=$FIREBLOCKS_API_PRIVATE_KEY_PATH \
FIREBLOCKS_CHAIN_ID=$FIREBLOCKS_CHAIN_ID \
fireblocks-json-rpc --http -- \
cast send $SBTSALE_PROXY \
  "upgradeTo(address)" \
  $SBTSALE_IMPLEMENTATION \
  --from $P2E_ADMIN \
  --unlocked \
  --rpc-url {} \
  --slow
```

> Tip: Add `--gas-price` / `--priority-gas-price` if you need to override Fireblocks defaults.
>
> The wrapped `cast send` command will broadcast once Fireblocks approves the transaction.

## Post-Upgrade Validation

1. Confirm the proxy now points at the new implementation:
   ```bash
   IMPLEMENTATION_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
   cast storage $SBTSALE_PROXY $IMPLEMENTATION_SLOT --rpc-url $RPC_URL
   ```
2. Check ownership and signer state remained intact:
   ```bash
   cast call $SBTSALE_PROXY "owner()(address)" --rpc-url $RPC_URL
   cast call $SBTSALE_PROXY "getSigner()(address)" --rpc-url $RPC_URL
   ```
3. (Optional) Re-run verification using `docs/VERIFY_CONTRACT.md`.
4. Update runbooks or changelogs with the new implementation address and relevant transaction hashes.

## Rollback

If you need to revert, repeat the upgrade command with the previous implementation address (kept in version control or release notes). No additional configuration changes are required, provided the old implementation is still compatible with the current storage layout.
