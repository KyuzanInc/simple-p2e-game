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

### Standard Deployment

Deploy contracts using Foundry scripts with a private key:

```bash
# Configure environment variables (see .envrc.sample)
export PRIVATE_KEY="your-private-key"
export RPC_URL="https://rpc.mainnet.oasys.games"
# ... other configuration variables

# Deploy SoulboundToken
forge script script/DeploySoulboundToken.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY

# Deploy SBTSale
forge script script/DeploySBTSale.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

### Fireblocks Deployment (Recommended for Production)

For enterprise-grade security using Fireblocks for key management and transaction signing, see the [Fireblocks Deployment Guide](./docs/FIREBLOCKS_DEPLOYMENT.md).

```bash
# Install Fireblocks JSON-RPC server
npm install -g @fireblocks/fireblocks-json-rpc

# Deploy with Fireblocks (see docs for full configuration)
fireblocks-json-rpc --http -- \
  forge script script/DeploySoulboundToken.s.sol:DeploySoulboundToken \
  --sender $DEPLOYER_ADDRESS \
  --slow \
  --broadcast \
  --unlocked \
  --rpc-url {}
```

For detailed setup and configuration, refer to [docs/FIREBLOCKS_DEPLOYMENT.md](./docs/FIREBLOCKS_DEPLOYMENT.md).
