# simple-p2e-game

A Play-to-Earn (P2E) project where players earn SMP (Simple) Tokens—a cryptocurrency—by playing a simple game that uses Cards, which are Soulbound Tokens (SBTs) with expiration dates.

## Getting Started

- For smart contract developers: Work from the root directory. Follow the instructions below.
  - Note: This project uses [Foundry](https://getfoundry.sh/). Please make sure Foundry is installed beforehand.
  - Note: This project uses [direnv](https://direnv.net/) for environment variable management. Please install and configure direnv.

### Prerequisites

```sh
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install direnv
# macOS
brew install direnv

# Linux
sudo apt-get install direnv

# Add direnv hook to your shell (~/.bashrc, ~/.zshrc, etc.)
eval "$(direnv hook bash)"  # or zsh, fish, etc.
# Restart your shell after adding the hook
```

### Setup

```sh
# Initialize git submodules (required for Foundry dependencies)
git submodule update --init --recursive

# Install dependencies
npm install

# Configure environment (see Deployment section below for details)
# For now, just acknowledge the .envrc.sample file
cat .envrc.sample

# Compile contracts
npm run build

# Run tests
npm test
```

## Contracts

- SimpleGame
  - The main contract that users interact with to play the game. (Not yet implemented.)
- [SBTSale](./src/SBTSale.sol)
  - Contract used to sell SBTs (Soulbound Tokens). Supports payment in SMP Token,
    native OAS, Wrapped OAS, and pOAS.
  - The price of each SBT is denominated in SMP tokens. When other tokens are used for payment, they are swapped to SMP via the Gaming DEX.
- [SoulboundToken](./src/SoulboundToken.sol)
  - An SBT (Soulbound Token) contract representing "Cards" used in the game.
  - The token itself does not have an expiration date. Ownership is permanent once minted, as with typical soulbound tokens. Expiration is handled separately by the game contract, not the token itself.
- SMP
  - An ERC-20 token used to purchase SBT Cards.
  - Deployed using the [L1StandardERC20Factory](https://docs.oasys.games/docs/architecture/hub-layer/contract#preset-contracts).

## Gaming Dex

A DEX built on the Oasys Hub, used for swapping SMP tokens. Gaming DEX is a fork of [Balancer V2](https://github.com/balancer/balancer-v2-monorepo).

- [testnet](https://testnet.gaming-dex.com/#/oasys-testnet/swap)
- [mainnet](https://www.gaming-dex.com/#/defiverse/swap)

## Deployment

This project supports environment-specific deployments:

- **Testnet**: Private key deployment (Chain ID: 9372)
- **Mainnet**: Fireblocks deployment (Chain ID: 248, recommended for production)

### Quick Start

```bash
# 1. Setup environment
npm run env:setup:testnet    # or env:setup:mainnet
npm run env:switch:testnet   # or env:switch:mainnet

# 2. Edit .envrc.testnet (or .envrc.mainnet) with your configuration

# 3. Deploy contracts (see docs for specific commands)

# 4. Setup roles and configurations
# Run the SetupRoles script after deployment
```

### Documentation

For detailed instructions:

- **[docs/DEPLOYMENT.md](./docs/DEPLOYMENT.md)** - Complete deployment guide
- **[docs/SETUP_ROLES.md](./docs/SETUP_ROLES.md)** - Post-deployment role configuration
- **[docs/UPGRADE.md](./docs/UPGRADE.md)** - Contract upgrade guide
- **[docs/VERIFY_CONTRACT.md](./docs/VERIFY_CONTRACT.md)** - Contract verification guide
- **[CLAUDE.md](./CLAUDE.md)** - Development commands and architecture
