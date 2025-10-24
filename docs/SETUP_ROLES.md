# Role Setup Guide

This guide explains how to set up necessary roles and configurations after deploying SoulboundToken and SBTSale contracts using Fireblocks.

## Prerequisites

1. Both SoulboundToken and SBTSale contracts must be deployed
2. Fireblocks CLI must be installed and configured
3. Required environment variables must be set

## Required Environment Variables

This project uses environment-specific configuration files (`.envrc.mainnet` or `.envrc.testnet`).

After deploying contracts, update your environment file with the deployed addresses:

```bash
# Edit your environment file (mainnet or testnet)
vim .envrc.mainnet  # or .envrc.testnet

# Add the following in the "Post-Deployment Configuration" section:
export SBT_PROXY="0x..."              # SoulboundToken Proxy address (from deployment output)
export SBTSALE_PROXY="0x..."          # SBTSale Proxy address (from deployment output)
export SIGNER_ADDRESS="0x..."         # Backend signer address for purchase verification

# Reload environment (if not using npm run env:switch:*)
direnv allow
```

**Note:** The setup script automatically detects whether to use Fireblocks (via `DEPLOYER_ADDRESS`) or private key (via `PRIVATE_KEY`). No additional configuration needed beyond what was used for deployment.

## What This Script Does

The `SetupRoles.s.sol` script performs the following operations:

1. **Set Signer** - Configures the authorized signer address in SBTSale for purchase signature verification
2. **Set SBT Contract** - Links the SBTSale contract to the SoulboundToken contract
3. **Grant MINTER_ROLE** - Grants SBTSale the ability to mint SBTs

## Execution

### Mainnet (Fireblocks)

```bash
# Switch to mainnet environment
npm run env:switch:mainnet

# Execute setup script with Fireblocks
fireblocks-json-rpc --http -- forge script \
  script/SetupRoles.s.sol:SetupRoles \
  --sender $DEPLOYER_ADDRESS \
  --slow \
  --broadcast \
  --unlocked \
  --rpc-url {}
```

### Testnet (Private Key)

```bash
# Switch to testnet environment
npm run env:switch:testnet

# Execute setup script with private key
forge script script/SetupRoles.s.sol:SetupRoles \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

## Verification

After running the script, verify the setup:

```bash
# Check Signer
cast call $SBTSALE_PROXY "getSigner()(address)" --rpc-url $RPC_URL

# Check SBT Contract
cast call $SBTSALE_PROXY "getSBTContract()(address)" --rpc-url $RPC_URL

# Check MINTER_ROLE
MINTER_ROLE=$(cast keccak "MINTER_ROLE")
cast call $SBT_PROXY \
  "hasRole(bytes32,address)(bool)" \
  $MINTER_ROLE \
  $SBTSALE_PROXY \
  --rpc-url $RPC_URL
```

Expected output:
- Signer should be the configured SIGNER_ADDRESS
- SBT Contract should be the SBT_PROXY address
- MINTER_ROLE check should return `true`

## Troubleshooting

### Error: "Ownable: caller is not the owner"
- **Cause**: DEPLOYER_ADDRESS is not the owner of SBTSale
- **Solution**: Use the address that was set as `P2E_ADMIN` during deployment

### Error: "AccessControlUnauthorizedAccount"
- **Cause**: DEPLOYER_ADDRESS doesn't have DEFAULT_ADMIN_ROLE on SoulboundToken
- **Solution**: Use the address that was set as `SBT_ADMIN` during deployment

### Error: "InvalidAddress"
- **Cause**: Wrong proxy address or contract doesn't implement required interface
- **Solution**: Verify SBT_PROXY and SBTSALE_PROXY addresses are correct (use Proxy, not Implementation)

### Script runs but no changes
- **Cause**: All configurations are already set correctly
- **Solution**: Check the console output - if values already match, the script will skip them

## Manual Setup (Alternative)

If you prefer to execute commands individually:

### Mainnet (Fireblocks)

```bash
# Switch environment
npm run env:switch:mainnet

# 1. Set Signer
fireblocks-json-rpc --http -- cast send $SBTSALE_PROXY \
  "setSigner(address)" $SIGNER_ADDRESS \
  --rpc-url {} \
  --unlocked \
  --from $DEPLOYER_ADDRESS

# 2. Set SBT Contract
fireblocks-json-rpc --http -- cast send $SBTSALE_PROXY \
  "setSBTContract(address)" $SBT_PROXY \
  --rpc-url {} \
  --unlocked \
  --from $DEPLOYER_ADDRESS

# 3. Grant MINTER_ROLE
MINTER_ROLE=$(cast keccak "MINTER_ROLE")
fireblocks-json-rpc --http -- cast send $SBT_PROXY \
  "grantRole(bytes32,address)" \
  $MINTER_ROLE \
  $SBTSALE_PROXY \
  --rpc-url {} \
  --unlocked \
  --from $DEPLOYER_ADDRESS
```

### Testnet (Private Key)

```bash
# Switch environment
npm run env:switch:testnet

# 1. Set Signer
cast send $SBTSALE_PROXY \
  "setSigner(address)" $SIGNER_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# 2. Set SBT Contract
cast send $SBTSALE_PROXY \
  "setSBTContract(address)" $SBT_PROXY \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# 3. Grant MINTER_ROLE
MINTER_ROLE=$(cast keccak "MINTER_ROLE")
cast send $SBT_PROXY \
  "grantRole(bytes32,address)" \
  $MINTER_ROLE \
  $SBTSALE_PROXY \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

## Additional Roles (Optional)

> **Note:** Examples below use Fireblocks commands. For testnet, replace with:
> ```bash
> cast send <CONTRACT> "<FUNCTION>" <ARGS> --rpc-url $RPC_URL --private-key $PRIVATE_KEY
> ```

### Grant Additional Admin Role

To add another admin to SoulboundToken:

```bash
# Switch to appropriate environment
npm run env:switch:mainnet  # or testnet

# Grant DEFAULT_ADMIN_ROLE
fireblocks-json-rpc --http -- cast send $SBT_PROXY \
  "grantRole(bytes32,address)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $NEW_ADMIN_ADDRESS \
  --rpc-url {} \
  --unlocked \
  --from $DEPLOYER_ADDRESS
```

### Grant Pauser Role

To add a pauser to SoulboundToken:

```bash
# Switch to appropriate environment
npm run env:switch:mainnet  # or testnet

PAUSER_ROLE=$(cast keccak "PAUSER_ROLE")
fireblocks-json-rpc --http -- cast send $SBT_PROXY \
  "grantRole(bytes32,address)" \
  $PAUSER_ROLE \
  $PAUSER_ADDRESS \
  --rpc-url {} \
  --unlocked \
  --from $DEPLOYER_ADDRESS
```

### Transfer Ownership of SBTSale

To transfer ownership (2-step process):

```bash
# Switch to appropriate environment
npm run env:switch:mainnet  # or testnet

# Step 1: Initiate transfer
fireblocks-json-rpc --http -- cast send $SBTSALE_PROXY \
  "transferOwnership(address)" $NEW_OWNER_ADDRESS \
  --rpc-url {} \
  --unlocked \
  --from $DEPLOYER_ADDRESS

# Step 2: New owner accepts (must be executed by new owner)
fireblocks-json-rpc --http -- cast send $SBTSALE_PROXY \
  "acceptOwnership()" \
  --rpc-url {} \
  --unlocked \
  --from $NEW_OWNER_ADDRESS
```

## Security Notes

- Always verify contract addresses before executing transactions
- Use multi-signature wallets for production admin addresses
- Keep your Fireblocks API credentials secure
- Test on testnet before executing on mainnet
- Verify all transactions on block explorer after execution
