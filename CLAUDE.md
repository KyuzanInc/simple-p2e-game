# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Play-to-Earn (P2E) game smart contract project built on the Oasys blockchain. The project uses Foundry for development and testing, with upgradeable contracts following OpenZeppelin standards.

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
forge script script/DeploySoulboundToken.s.sol --rpc-url $RPC_URL --broadcast
forge script script/DeploySBTSale.s.sol --rpc-url $RPC_URL --broadcast
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
- Network configuration: `RPC_URL`, `PRIVATE_KEY`
- SBT parameters: name, symbol, base URI, admin address
- SBTSale parameters: liquidity pool, recipients, pricing, ratios

### Key Design Patterns

1. **Upgradeable Contracts**: Using OpenZeppelin's upgradeable pattern for future flexibility
2. **Role-Based Access**: AccessControl for minting and admin operations
3. **Soulbound Implementation**: Tokens cannot be transferred after minting
4. **Multi-Token Payment**: Supports various payment methods with automatic DEX swaps
5. **Revenue Distribution**: Automated splitting between burning, liquidity, and revenue