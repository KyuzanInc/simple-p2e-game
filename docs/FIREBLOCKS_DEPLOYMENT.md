# Fireblocks Deployment Guide

This guide explains how to deploy smart contracts using Fireblocks for secure key management and transaction signing.

## Overview

Fireblocks provides enterprise-grade security for managing private keys and signing blockchain transactions. By integrating Fireblocks with Foundry, you can deploy and interact with smart contracts without exposing private keys on your local machine.

## Prerequisites

- Node.js and npm installed
- Foundry installed
- A Fireblocks account with:
  - API Key
  - API Secret Key file
  - Configured Vault Account
  - Whitelisted contract deployment and interaction permissions

## Setup

### 1. Install Fireblocks JSON-RPC Server

Install the Fireblocks JSON-RPC server globally:

```bash
npm install -g @fireblocks/fireblocks-json-rpc
```

### 2. Configure Environment Variables

Create or update your `.envrc` file with Fireblocks credentials:

```bash
# Fireblocks Configuration
export FIREBLOCKS_API_KEY="your-api-key-uuid"
export FIREBLOCKS_API_PRIVATE_KEY_PATH="/path/to/fireblocks_secret.key"
export FIREBLOCKS_VAULT_ACCOUNT_IDS="0"  # Your vault account ID
export FIREBLOCKS_CHAIN_ID="248"  # 248 for Oasys Hub Layer

# Deployment Configuration
export DEPLOYER_ADDRESS="0x..."  # Address from your Fireblocks vault account
export RPC_URL="https://rpc.mainnet.oasys.games"

# SoulboundToken Configuration
export SBT_NAME="YourSBTName"
export SBT_SYMBOL="YSBT"
export SBT_BASE_URI="https://your-api.com/metadata/"
export SBT_ADMIN="0x..."  # Admin address

# SBTSale Configuration
export SBTSALE_LIQUIDITY_POOL="0x..."
export SBTSALE_MINTER="0x..."
export SBTSALE_POAS_MINTER="0x..."
export SBTSALE_REVENUE_RECIPIENT="0x..."
export SBTSALE_LIQUIDITY_RECIPIENT="0x..."
export SBTSALE_PRICE="1000000000000000000"  # 1 token in wei
export SBTSALE_BURN_RATIO="50"
export SBTSALE_LIQUIDITY_RATIO="30"
export SBTSALE_REVENUE_RATIO="20"
```

Load the environment variables with direnv:

```bash
# Allow direnv for this directory (direnv must be installed and configured)
direnv allow

# Verify Fireblocks environment variables are loaded
env | grep FIREBLOCKS
```

Expected output:
```
FIREBLOCKS_API_KEY=your-api-key-uuid
FIREBLOCKS_API_PRIVATE_KEY_PATH=/path/to/fireblocks_secret.key
FIREBLOCKS_VAULT_ACCOUNT_IDS=0
FIREBLOCKS_CHAIN_ID=248
```

### 3. Get Your Fireblocks Vault Account Address

Retrieve the address associated with your Fireblocks vault account:

```bash
# Using Fireblocks API or Console
# Set this address as DEPLOYER_ADDRESS in your .envrc
```

## Deployment

### Option 1: Deploy with Modified Script (Recommended)

Modify the deployment script to use an address instead of a private key.

**Update `script/DeploySoulboundToken.s.sol`:**

```solidity
function run() external returns (TransparentUpgradeableProxy proxy) {
    // Use address from environment variable instead of private key
    address deployer = vm.envAddress("DEPLOYER_ADDRESS");
    vm.startBroadcast(deployer);

    string memory name = vm.envString("SBT_NAME");
    string memory symbol = vm.envString("SBT_SYMBOL");
    string memory baseURI = vm.envString("SBT_BASE_URI");
    address admin = vm.envAddress("SBT_ADMIN");

    // ... rest of the deployment code

    vm.stopBroadcast();
}
```

Then deploy using:

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

### Option 2: Deploy with Existing Script (No Modifications)

If you don't want to modify the script, you can use the existing script that reads `PRIVATE_KEY`. However, you still need to provide the sender address:

```bash
FIREBLOCKS_API_KEY=$FIREBLOCKS_API_KEY \
FIREBLOCKS_API_PRIVATE_KEY_PATH=$FIREBLOCKS_API_PRIVATE_KEY_PATH \
FIREBLOCKS_CHAIN_ID=$FIREBLOCKS_CHAIN_ID \
PRIVATE_KEY=0x0000000000000000000000000000000000000000000000000000000000000001 \
fireblocks-json-rpc --http -- \
forge script script/DeploySoulboundToken.s.sol:DeploySoulboundToken \
--sender $DEPLOYER_ADDRESS \
--slow \
--broadcast \
--unlocked \
--rpc-url {}
```

**Note:** The `PRIVATE_KEY` value is ignored when using Fireblocks, but the script might require it to be set. Use a dummy value as shown above.

### Deploy SBTSale Contract

Similarly, deploy the SBTSale contract:

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

## Important Flags Explained

- `--sender <address>`: Specifies the address from your Fireblocks vault account that will sign transactions
- `--slow`: Executes transactions sequentially (recommended to avoid nonce issues)
- `--broadcast`: Actually broadcasts transactions to the network (omit for dry run)
- `--unlocked`: Indicates that the sender account is managed externally (by Fireblocks)
- `--rpc-url {}`: Empty braces let `fireblocks-json-rpc` automatically configure the RPC URL

## Verification

After deployment, verify your contracts on the block explorer:

```bash
forge verify-contract \
  --chain-id 248 \
  --constructor-args $(cast abi-encode "constructor()" ) \
  <CONTRACT_ADDRESS> \
  src/SoulboundToken.sol:SoulboundToken \
  --etherscan-api-key <YOUR_API_KEY>
```

## Testnet Deployment

For testnet deployments (Oasys Testnet Hub):

```bash
export FIREBLOCKS_CHAIN_ID="9372"  # Oasys Testnet Hub Layer
export RPC_URL="https://rpc.testnet.oasys.games"
```

Then follow the same deployment steps as above.

## Troubleshooting

### Transaction Stuck or Failing

1. **Check Fireblocks Console**: Review the transaction status in your Fireblocks workspace
2. **Transaction Policy**: Ensure your Fireblocks Transaction Authorization Policy (TAP) allows contract deployment and interactions
3. **Whitelisting**: Verify that the target contract addresses are whitelisted in Fireblocks
4. **Gas Settings**: Ensure sufficient gas limits are configured

### "Invalid Sender" Error

- Verify that `DEPLOYER_ADDRESS` matches the address in your Fireblocks vault account
- Ensure the vault account ID in `FIREBLOCKS_VAULT_ACCOUNT_IDS` is correct

### "RPC URL Not Found" Error

- Check that `FIREBLOCKS_CHAIN_ID` matches the network you're deploying to:
  - Oasys Mainnet Hub: `248`
  - Oasys Testnet Hub: `9372`

### Nonce Issues

- Use the `--slow` flag to ensure transactions are sent sequentially
- Check for pending transactions in Fireblocks Console

## Security Best Practices

1. **API Key Security**: Never commit your Fireblocks API key or secret key to version control
2. **Access Control**: Use Fireblocks' Transaction Authorization Policy (TAP) to control who can approve deployments
3. **Whitelisting**: Configure contract address whitelists in Fireblocks for additional security
4. **Audit Logs**: Regularly review Fireblocks audit logs for all deployment activities
5. **Multi-signature**: Consider enabling multi-signature approval for production deployments

## Additional Resources

- [Fireblocks Documentation](https://developers.fireblocks.com/)
- [Fireblocks Ethereum Development Guide](https://developers.fireblocks.com/docs/ethereum-smart-contract-development)
- [Foundry Documentation](https://book.getfoundry.sh/)
- [Oasys Documentation](https://docs.oasys.games/)
