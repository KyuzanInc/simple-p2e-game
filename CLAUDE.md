# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Play-to-Earn (P2E) game smart contract project built on the Oasys blockchain. The project uses Foundry for development and testing, with upgradeable contracts following OpenZeppelin standards.

## Git Repository Structure

- **origin**: `KyuzanInc/simple-p2e-game` - The main fork repository where PRs should be created
- **upstream**: `oasysgames/simple-p2e-game` - The original repository (used for syncing updates)

**Important**: When creating PRs, always create them against the `origin` repository (KyuzanInc), not upstream.

## Development Commands

```bash
# Install dependencies
npm install

# Build contracts
npm run build
forge build

# Run all tests with verbose output
npm test
forge test -vvv

# Watch mode for development
npm run build:watch
npm run test:watch
forge test -vvv --watch

# Format Solidity code
npm run fmt
forge fmt

# Generate deployer contracts for tests
npm run script:GenerateDeployers

# Deploy contracts (requires environment configuration)
# Standard deployment (with private key)
forge script script/DeploySoulboundToken.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
forge script script/DeploySBTSale.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY

# Deploy with Fireblocks (recommended for production - see docs/DEPLOYMENT.md)
# Note: Requires FIREBLOCKS_API_KEY, FIREBLOCKS_API_PRIVATE_KEY_PATH, FIREBLOCKS_CHAIN_ID
FIREBLOCKS_API_KEY=$FIREBLOCKS_API_KEY \
FIREBLOCKS_API_PRIVATE_KEY_PATH=$FIREBLOCKS_API_PRIVATE_KEY_PATH \
FIREBLOCKS_CHAIN_ID=$FIREBLOCKS_CHAIN_ID \
fireblocks-json-rpc --http -- forge script script/DeploySoulboundToken.s.sol:DeploySoulboundToken --sender $DEPLOYER_ADDRESS --slow --broadcast --unlocked --rpc-url {}

FIREBLOCKS_API_KEY=$FIREBLOCKS_API_KEY \
FIREBLOCKS_API_PRIVATE_KEY_PATH=$FIREBLOCKS_API_PRIVATE_KEY_PATH \
FIREBLOCKS_CHAIN_ID=$FIREBLOCKS_CHAIN_ID \
fireblocks-json-rpc --http -- forge script script/DeploySBTSale.s.sol:DeploySBTSale --sender $DEPLOYER_ADDRESS --slow --broadcast --unlocked --rpc-url {}

# Setup roles and configurations after deployment (see docs/SETUP_ROLES.md)
# Standard setup (with private key)
forge script script/SetupRoles.s.sol:SetupRoles --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY

# Setup with Fireblocks (recommended for production)
FIREBLOCKS_API_KEY=$FIREBLOCKS_API_KEY \
FIREBLOCKS_API_PRIVATE_KEY_PATH=$FIREBLOCKS_API_PRIVATE_KEY_PATH \
FIREBLOCKS_CHAIN_ID=$FIREBLOCKS_CHAIN_ID \
fireblocks-json-rpc --http -- forge script script/SetupRoles.s.sol:SetupRoles --sender $DEPLOYER_ADDRESS --slow --broadcast --unlocked --rpc-url {}
```

## Architecture Overview

### Core Contracts

1. **SoulboundToken** (`contracts/SoulboundToken.sol`)
   - ERC721 Soulbound Token (SBT) implementation representing game "Cards"
   - Non-transferable tokens (soulbound) with permanent ownership
   - Upgradeable proxy pattern with role-based access control
   - Minter role required for minting operations

2. **SBTSale** (`contracts/SBTSale.sol`)
   - Manages SBT sales with multiple payment token support (SMP, OAS, WOAS, pOAS)
   - Integrates with Gaming DEX (Balancer V2 fork) for token swaps
   - Handles SMP token burning, liquidity provision, and revenue distribution
   - Uses upgradeable proxy pattern with owner and reentrancy protection

3. **SimpleGame** (Not yet implemented)
   - Main game contract for user interactions
   - Will handle game logic and expiration dates separately from the SBT tokens

### Integration Points

- **Gaming DEX**: Balancer V2 fork on Oasys Hub for SMP token swaps
- **L1StandardERC20Factory**: Used for deploying the SMP ERC-20 token on Oasys
- **pOAS Minter**: Interface for minting pOAS tokens during sales

### Testing Infrastructure

- Test utilities in `contracts/test-utils/` including mock contracts for:
  - Balancer V2 components (Vault, WeightedPoolFactory)
  - Token mocks (MockSMP, MockPOAS, WOAS)
  - Helper contracts for DEX interactions
- Comprehensive test suites in `test/` directory

### Deployment Configuration

Environment variables required (see `.envrc.sample`):
- Network configuration: `RPC_URL`, `PRIVATE_KEY` (or Fireblocks credentials)
- SBT parameters: name, symbol, base URI, admin address
- SBTSale parameters: liquidity pool, recipients, pricing, ratios

For production deployments, Fireblocks integration is available for secure key management. See `docs/DEPLOYMENT.md` for detailed configuration and usage instructions.

**Fireblocks Environment Variables (Optional):**
- `FIREBLOCKS_API_KEY`: Fireblocks API key (UUID format)
- `FIREBLOCKS_API_PRIVATE_KEY_PATH`: Path to Fireblocks API secret key file
- `FIREBLOCKS_VAULT_ACCOUNT_IDS`: Vault account ID(s)
- `FIREBLOCKS_CHAIN_ID`: Chain ID (248 for Oasys Mainnet, 9372 for Testnet)
- `DEPLOYER_ADDRESS`: Deployer address from Fireblocks vault account

### Key Design Patterns

1. **Upgradeable Contracts**: Using OpenZeppelin's upgradeable pattern for future flexibility
2. **Role-Based Access**: AccessControl for minting and admin operations
3. **Soulbound Implementation**: Tokens cannot be transferred after minting
4. **Multi-Token Payment**: Supports various payment methods with automatic DEX swaps
5. **Revenue Distribution**: Automated splitting between burning, liquidity, and revenue