# Deployment Guide

This guide explains how to deploy smart contracts for the simple-p2e-game project on the Oasys blockchain.

## Overview

The deployment scripts support two methods:

1. **Fireblocks Deployment (Recommended for Production)** - Enterprise-grade security with hardware-backed key management
2. **Standard Deployment** - Direct private key deployment for development and testing

The deployment scripts automatically detect which method to use based on your environment configuration.

## Prerequisites

### Common Prerequisites

- Node.js and npm installed
- Foundry installed
- direnv installed and configured

### Additional Prerequisites for Fireblocks

- A Fireblocks account with:
  - API Key
  - API Secret Key file
  - Configured Vault Account
  - Whitelisted contract deployment and interaction permissions

## Environment Management

This project supports environment-specific configurations for mainnet and testnet deployments.

### Setup Environment-Specific Configuration

**Using npm scripts (recommended):**

```bash
# Create environment configuration files
npm run env:setup:testnet   # Creates .envrc.testnet
npm run env:setup:mainnet   # Creates .envrc.mainnet

# Edit the created files with your configuration
# Then switch to the environment you want to use
npm run env:switch:testnet  # Use testnet configuration
npm run env:switch:mainnet  # Use mainnet configuration

# Verify current environment
npm run env:status
```

**Manual setup:**

```bash
# Copy sample files
cp .envrc.testnet.sample .envrc.testnet
cp .envrc.mainnet.sample .envrc.mainnet

# Edit with your configuration
vim .envrc.testnet
vim .envrc.mainnet

# Create symbolic link to the environment you want
ln -s .envrc.testnet .envrc
direnv allow
```

## Quick Start

### Option 1: Fireblocks Deployment (Recommended)

**1. Install Fireblocks JSON-RPC Server**

```bash
npm install -g @fireblocks/fireblocks-json-rpc
```

**2. Setup Environment Configuration**

```bash
# Create environment-specific configuration file
npm run env:setup:mainnet   # For production
# or
npm run env:setup:testnet   # For testing

# Edit the created file (.envrc.mainnet or .envrc.testnet) with your Fireblocks credentials:
# - DEPLOYER_ADDRESS: Address from your Fireblocks vault account
# - FIREBLOCKS_API_KEY: Your API key UUID
# - FIREBLOCKS_API_PRIVATE_KEY_PATH: Path to your secret key file
# - FIREBLOCKS_VAULT_ACCOUNT_IDS: Your vault account ID
# - FIREBLOCKS_CHAIN_ID: 248 for Mainnet, 9372 for Testnet
# - Contract configuration variables (SBT_*, P2E_*)

# Switch to the environment you configured
npm run env:switch:mainnet
# or
npm run env:switch:testnet
```

**3. Verify Environment**

```bash
# Check current environment
npm run env:status

# Verify Fireblocks configuration
env | grep FIREBLOCKS
env | grep DEPLOYER_ADDRESS
```

**4. Deploy Contracts**

Deploy SoulboundToken:

```bash
FIREBLOCKS_API_KEY=$FIREBLOCKS_API_KEY \
FIREBLOCKS_API_PRIVATE_KEY_PATH=$FIREBLOCKS_API_PRIVATE_KEY_PATH \
FIREBLOCKS_CHAIN_ID=$FIREBLOCKS_CHAIN_ID \
fireblocks-json-rpc --http -- \
forge script script/DeploySoulboundToken.s.sol:DeploySoulboundToken \
--sender $DEPLOYER_ADDRESS \
--slow \
--broadcast \
--unlocked \
--rpc-url {}
```

Deploy SBTSale:

```bash
FIREBLOCKS_API_KEY=$FIREBLOCKS_API_KEY \
FIREBLOCKS_API_PRIVATE_KEY_PATH=$FIREBLOCKS_API_PRIVATE_KEY_PATH \
FIREBLOCKS_CHAIN_ID=$FIREBLOCKS_CHAIN_ID \
fireblocks-json-rpc --http -- \
forge script script/DeploySBTSale.s.sol:DeploySBTSale \
--sender $DEPLOYER_ADDRESS \
--slow \
--broadcast \
--unlocked \
--rpc-url {}
```

### Option 2: Standard Deployment

**1. Setup Environment Configuration**

```bash
# Create environment-specific configuration file
npm run env:setup:mainnet   # For production
# or
npm run env:setup:testnet   # For testing

# Edit the created file (.envrc.mainnet or .envrc.testnet):
# - Set RPC_URL (https://rpc.mainnet.oasys.games or https://rpc.testnet.oasys.games)
# - Set PRIVATE_KEY with your private key
# - Comment out all FIREBLOCKS_* and DEPLOYER_ADDRESS variables
# - Configure contract variables (SBT_*, P2E_*)

# Switch to the environment you configured
npm run env:switch:mainnet
# or
npm run env:switch:testnet
```

**2. Verify Environment**

```bash
# Check current environment
npm run env:status

# Verify configuration
env | grep -E "^(RPC_URL|PRIVATE_KEY|SBT_|P2E_)"
```

**3. Deploy Contracts**

Deploy SoulboundToken:

```bash
forge script script/DeploySoulboundToken.s.sol:DeploySoulboundToken \
--rpc-url $RPC_URL \
--broadcast \
--private-key $PRIVATE_KEY
```

Deploy SBTSale:

```bash
forge script script/DeploySBTSale.s.sol:DeploySBTSale \
--rpc-url $RPC_URL \
--broadcast \
--private-key $PRIVATE_KEY
```

## How the Deployment Scripts Work

The deployment scripts automatically detect which method to use:

**Fireblocks Deployment:**
- If `DEPLOYER_ADDRESS` environment variable is set
- Uses `vm.startBroadcast(deployer)` with the address
- Requires `--unlocked` flag when running forge script
- Transaction signing is handled by Fireblocks JSON-RPC server
- **RPC URL**: Automatically configured by `fireblocks-json-rpc` based on `FIREBLOCKS_CHAIN_ID`
- **`RPC_URL` is ignored** when using Fireblocks

**Standard Deployment:**
- If `DEPLOYER_ADDRESS` is NOT set
- Falls back to `PRIVATE_KEY` environment variable
- Uses `vm.startBroadcast(deployerPrivateKey)` with the private key
- Standard private key signing
- **RPC URL**: Must be explicitly set via `RPC_URL` environment variable
- Passed to forge script with `--rpc-url $RPC_URL`

## Network Configuration

### Available Networks

| Network | RPC URL | Chain ID (Fireblocks) |
|---------|---------|----------------------|
| **Mainnet** (Oasys Hub Layer) | `https://rpc.mainnet.oasys.games` | `248` |
| **Testnet** (Oasys Testnet Hub Layer) | `https://rpc.testnet.oasys.games` | `9372` |

### Configuration Examples

**Mainnet:**
```bash
export RPC_URL="https://rpc.mainnet.oasys.games"
export FIREBLOCKS_CHAIN_ID="248"  # For Fireblocks only
```

**Testnet:**
```bash
export RPC_URL="https://rpc.testnet.oasys.games"
export FIREBLOCKS_CHAIN_ID="9372"  # For Fireblocks only
```

## Configuration Variables

See `.envrc.sample` for a complete list of required environment variables:

### SoulboundToken Configuration

- `SBT_NAME`: Token name
- `SBT_SYMBOL`: Token symbol
- `SBT_BASE_URI`: Base URI for token metadata
- `SBT_ADMIN`: Admin address (can upgrade proxy and grant roles)

### SBTSale Configuration

- `P2E_POAS_MINTER`: pOAS minter contract address
- `P2E_LIQUIDITY_POOL`: WOAS-SMP liquidity pool address
- `P2E_LP_RECIPIENT`: Recipient of LP tokens
- `P2E_REVENUE_RECIPIENT`: Recipient of protocol revenue
- `P2E_SMP_BASE_PRICE`: Base price per NFT in SMP (wei)
- `P2E_SMP_BURN_RATIO`: Ratio of SMP to burn (basis points)
- `P2E_SMP_LIQUIDITY_RATIO`: Ratio of SMP for liquidity (basis points)
- `P2E_ADMIN`: Proxy admin and initial owner

## Verification

After deployment, verify your contracts on the block explorer:

```bash
forge verify-contract \
  --chain-id 248 \
  --constructor-args $(cast abi-encode "constructor()") \
  <CONTRACT_ADDRESS> \
  src/SoulboundToken.sol:SoulboundToken \
  --etherscan-api-key <YOUR_API_KEY>
```

## Command Flags Explained

### Fireblocks Deployment Flags

- `--sender <address>`: Address from Fireblocks vault account that signs transactions
- `--slow`: Executes transactions sequentially (recommended to avoid nonce issues)
- `--broadcast`: Broadcasts transactions to the network (omit for dry run)
- `--unlocked`: Indicates sender account is managed externally (by Fireblocks)
- `--rpc-url {}`: **Empty braces** - lets `fireblocks-json-rpc` configure RPC URL automatically based on `FIREBLOCKS_CHAIN_ID`
  - Chain ID 248 → `https://rpc.mainnet.oasys.games`
  - Chain ID 9372 → `https://rpc.testnet.oasys.games`

### Standard Deployment Flags

- `--rpc-url <url>`: **Explicit RPC endpoint URL** from `$RPC_URL` environment variable
  - Must be manually set in `.envrc`
  - Example: `--rpc-url https://rpc.mainnet.oasys.games`
- `--broadcast`: Broadcasts transactions to the network (omit for dry run)
- `--private-key <key>`: Private key for signing transactions from `$PRIVATE_KEY` environment variable

## Troubleshooting

### Fireblocks Issues

**Transaction Stuck or Failing**
1. Check Fireblocks Console for transaction status
2. Verify Transaction Authorization Policy (TAP) allows contract deployment
3. Ensure target addresses are whitelisted in Fireblocks
4. Check gas settings are sufficient

**"Invalid Sender" Error**
- Verify `DEPLOYER_ADDRESS` matches your Fireblocks vault account address
- Ensure `FIREBLOCKS_VAULT_ACCOUNT_IDS` is correct

**"RPC URL Not Found" Error**
- Check `FIREBLOCKS_CHAIN_ID` matches the network:
  - Oasys Mainnet Hub: `248`
  - Oasys Testnet Hub: `9372`

**Nonce Issues**
- Use `--slow` flag to send transactions sequentially
- Check for pending transactions in Fireblocks Console

### Standard Deployment Issues

**"Insufficient Funds" Error**
- Ensure deployer account has enough OAS for gas fees

**"Nonce Too Low" Error**
- Wait for pending transactions to complete
- Or use `--nonce <value>` flag to specify nonce manually

**Private Key Not Found**
- Verify `PRIVATE_KEY` environment variable is set
- Run `env | grep PRIVATE_KEY` to check

## Security Best Practices

### For Fireblocks Deployment

1. **API Key Security**: Never commit Fireblocks API keys or secret keys to version control
2. **Access Control**: Use Transaction Authorization Policy (TAP) to control deployment approvals
3. **Whitelisting**: Configure contract address whitelists for additional security
4. **Audit Logs**: Regularly review Fireblocks audit logs
5. **Multi-signature**: Enable multi-signature approval for production deployments

### For Standard Deployment

1. **Private Key Security**: Never commit private keys to version control
2. **Environment Files**: Add `.envrc` to `.gitignore` (already configured)
3. **Hardware Wallets**: Consider using hardware wallets for production
4. **Key Rotation**: Rotate private keys regularly
5. **Separate Keys**: Use different keys for development and production

## Additional Resources

- [Fireblocks Documentation](https://developers.fireblocks.com/)
- [Fireblocks Ethereum Development Guide](https://developers.fireblocks.com/docs/ethereum-smart-contract-development)
- [Foundry Documentation](https://book.getfoundry.sh/)
- [Foundry Deployment Guide](https://book.getfoundry.sh/tutorials/solidity-scripting)
- [Oasys Documentation](https://docs.oasys.games/)
- [direnv Documentation](https://direnv.net/)
