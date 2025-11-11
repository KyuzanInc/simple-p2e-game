# Base URI Setup Guide

This guide explains how to update the base URI for the SoulboundToken contract metadata using Fireblocks or private key.

## Prerequisites

1. SoulboundToken contract must be deployed
2. Fireblocks CLI must be installed and configured (for Fireblocks deployment)
3. Required environment variables must be set
4. Deployer must have `DEFAULT_ADMIN_ROLE` on the SoulboundToken contract

## Required Environment Variables

This project uses environment-specific configuration files (`.envrc.mainnet` or `.envrc.testnet`).

You can use the provided sample files as templates:
- `.envrc.mainnet.sample` - For mainnet configuration
- `.envrc.testnet.sample` - For testnet configuration

Update your environment file with the required values:

```bash
# Copy sample file if you haven't already
cp .envrc.mainnet.sample .envrc.mainnet  # or .envrc.testnet.sample to .envrc.testnet

# Edit your environment file (mainnet or testnet)
vim .envrc.mainnet  # or .envrc.testnet

# Update the SBT_BASE_URI to the new value you want to set:
export SBT_PROXY="0x..."                    # SoulboundToken Proxy address (from deployment output)
export SBT_BASE_URI="https://..."           # New base URI for token metadata

# Reload environment (if not using npm run env:switch:*)
direnv allow
```

**Note:**
- This script uses the existing `SBT_BASE_URI` environment variable (same as deployment)
- Simply update `SBT_BASE_URI` to the new value you want to set on the contract
- The setup script automatically detects whether to use Fireblocks (via `DEPLOYER_ADDRESS`) or private key (via `PRIVATE_KEY`)
- No additional configuration needed beyond what was used for deployment

## What This Script Does

The `SetBaseURI.s.sol` script performs the following operation:

1. **Verify Admin Role** - Checks that the deployer has `DEFAULT_ADMIN_ROLE` on the SoulboundToken contract
2. **Update Base URI** - Sets the new base URI for token metadata

The base URI is used as a prefix for all token URIs. For example:
- Base URI (`SBT_BASE_URI`): `https://example.com/metadata/`
- Token #1 URI: `https://example.com/metadata/1`
- Token #2 URI: `https://example.com/metadata/2`

**Important:** The script reads the value from the `SBT_BASE_URI` environment variable, so make sure to update it to your desired new base URI before running the script.

## Execution

### Mainnet (Fireblocks)

```bash
# Switch to mainnet environment (this loads NEW_BASE_URI from .envrc.mainnet)
npm run env:switch:mainnet

# Execute script with Fireblocks
FIREBLOCKS_API_KEY=$FIREBLOCKS_API_KEY \
FIREBLOCKS_API_PRIVATE_KEY_PATH=$FIREBLOCKS_API_PRIVATE_KEY_PATH \
FIREBLOCKS_CHAIN_ID=$FIREBLOCKS_CHAIN_ID \
fireblocks-json-rpc --http -- \
forge script script/SetBaseURI.s.sol:SetBaseURI \
--sender $DEPLOYER_ADDRESS \
--slow \
--broadcast \
--unlocked \
--rpc-url {}
```

### Testnet (Private Key)

```bash
# Switch to testnet environment (this loads NEW_BASE_URI from .envrc.testnet)
npm run env:switch:testnet

# Execute script with private key
forge script script/SetBaseURI.s.sol:SetBaseURI \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

## Verification

After running the script, verify the base URI was updated:

```bash
# Get tokenURI for a minted token (replace TOKEN_ID with actual ID)
TOKEN_ID=1
cast call $SBT_PROXY \
  "tokenURI(uint256)(string)" \
  $TOKEN_ID \
  --rpc-url $RPC_URL

# The output should be: NEW_BASE_URI + TOKEN_ID
# Example: https://your-metadata-server.com/tokens/1
```

**Note:** You can only verify the base URI by checking a token's URI if tokens have been minted. If no tokens exist yet, the update will still be successful but cannot be verified until after minting.

## Troubleshooting

### Error: "AccessControlUnauthorizedAccount"
- **Cause**: `DEPLOYER_ADDRESS` doesn't have `DEFAULT_ADMIN_ROLE` on SoulboundToken
- **Solution**: Use the address that was set as `SBT_ADMIN` during deployment

### Error: "InvalidBaseURI"
- **Cause**: The `SBT_BASE_URI` is an empty string
- **Solution**: Ensure `SBT_BASE_URI` is set to a valid non-empty string

### Error: "Missing DEFAULT_ADMIN_ROLE"
- **Cause**: Deployer account lacks the required admin role
- **Solution**:
  1. Check who has `DEFAULT_ADMIN_ROLE` using cast:
     ```bash
     DEFAULT_ADMIN_ROLE=0x0000000000000000000000000000000000000000000000000000000000000000
     cast call $SBT_PROXY "hasRole(bytes32,address)(bool)" $DEFAULT_ADMIN_ROLE $DEPLOYER_ADDRESS --rpc-url $RPC_URL
     ```
  2. Use the correct admin address or grant the role to your deployer

### Wrong proxy address
- **Cause**: Using implementation address instead of proxy address
- **Solution**: Verify `SBT_PROXY` is the TransparentUpgradeableProxy address, not the implementation

## Base URI Format Guidelines

When setting the base URI, follow these best practices:

1. **Include trailing slash**: Use `https://example.com/metadata/` not `https://example.com/metadata`
2. **Use HTTPS**: Ensure secure connection for metadata
3. **Test accessibility**: Verify the metadata server is accessible before updating
4. **Plan token IDs**: Ensure your metadata server can serve files at `{baseURI}{tokenId}`

### Example Base URIs

```bash
# IPFS (with gateway)
export SBT_BASE_URI="https://gateway.pinata.cloud/ipfs/QmHash/"

# Custom server
export SBT_BASE_URI="https://metadata.yourgame.com/nft/"

# Arweave
export SBT_BASE_URI="https://arweave.net/TxHash/"
```

**Note:** The sample environment files (`.envrc.mainnet.sample` and `.envrc.testnet.sample`) include the `SBT_BASE_URI` variable. Simply update this value to your new metadata hosting solution before running the script.

## Security Notes

- Always verify the new base URI is correct before executing the transaction
- Test the metadata URLs are accessible (e.g., `curl https://your-uri/1`) before updating
- Use multi-signature wallets for production admin addresses
- Keep your Fireblocks API credentials secure
- Test on testnet before executing on mainnet
- Verify the transaction on block explorer after execution
- Consider the immutability implications - while base URI can be updated, this should be done carefully as it affects all token metadata

## Related Documentation

- [Deployment Guide](DEPLOYMENT.md) - For initial contract deployment
- [Role Setup Guide](SETUP_ROLES.md) - For post-deployment role configuration
- [OpenZeppelin ERC721 Documentation](https://docs.openzeppelin.com/contracts/4.x/api/token/erc721#ERC721-tokenURI-uint256-) - For understanding tokenURI behavior
