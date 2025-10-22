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

# Configure environment variables
cp .envrc.sample .envrc
# Edit .envrc with your configuration
direnv allow

# Verify environment variables are loaded
env | grep -E "^(RPC_URL|PRIVATE_KEY|SBT_|P2E_)"

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

This project supports two deployment methods:

1. **Fireblocks Deployment (Recommended for Production)** - Enterprise-grade security with Fireblocks
2. **Standard Deployment** - Direct private key deployment for development

### Quick Start

**Fireblocks Deployment (Recommended):**

```bash
# Install Fireblocks JSON-RPC server
npm install -g @fireblocks/fireblocks-json-rpc

# Configure .envrc with Fireblocks credentials
export DEPLOYER_ADDRESS="0x..."  # Your Fireblocks vault address
export FIREBLOCKS_API_KEY="..."
export FIREBLOCKS_API_PRIVATE_KEY_PATH="..."
# ... see docs/DEPLOYMENT.md for full configuration

# Deploy
fireblocks-json-rpc --http -- \
  forge script script/DeploySoulboundToken.s.sol:DeploySoulboundToken \
  --sender $DEPLOYER_ADDRESS \
  --slow \
  --broadcast \
  --unlocked \
  --rpc-url {}
```

**Standard Deployment:**

```bash
# Configure .envrc with private key
export PRIVATE_KEY="0x..."
export RPC_URL="https://rpc.mainnet.oasys.games"
# DO NOT set DEPLOYER_ADDRESS

# Deploy
forge script script/DeploySoulboundToken.s.sol:DeploySoulboundToken \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

For detailed setup, configuration, and troubleshooting, see **[docs/DEPLOYMENT.md](./docs/DEPLOYMENT.md)**.
