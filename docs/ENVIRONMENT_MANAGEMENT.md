# Environment Management Guide

This guide explains how to manage multiple environment configurations (mainnet, testnet) for deployment.

## Overview

The project supports environment-specific configuration files to manage different deployment targets:

- `.envrc.mainnet` - Production environment (Oasys Mainnet)
- `.envrc.testnet` - Testing environment (Oasys Testnet)

## Initial Setup

### 1. Create Environment-Specific Configuration Files

```bash
# Copy sample files to create your configuration
cp .envrc.mainnet.sample .envrc.mainnet
cp .envrc.testnet.sample .envrc.testnet
```

### 2. Configure Each Environment

**Edit `.envrc.mainnet` for production:**

```bash
# Network: Mainnet
export RPC_URL=https://rpc.mainnet.oasys.games

# Fireblocks (Recommended for Production)
export DEPLOYER_ADDRESS="0x..."
export FIREBLOCKS_API_KEY="your-mainnet-api-key"
export FIREBLOCKS_API_PRIVATE_KEY_PATH="/path/to/fireblocks_secret.key"
export FIREBLOCKS_VAULT_ACCOUNT_IDS="0"
export FIREBLOCKS_CHAIN_ID="248"

# Contract Configuration
export SBT_NAME="ProductionSBT"
export SBT_ADMIN="0x..."
# ... other mainnet settings
```

**Edit `.envrc.testnet` for testing:**

```bash
# Network: Testnet
export RPC_URL=https://rpc.testnet.oasys.games

# For testing, you can use either Fireblocks or private key
export PRIVATE_KEY="0x..."

# Or Fireblocks for testnet
# export DEPLOYER_ADDRESS="0x..."
# export FIREBLOCKS_API_KEY="your-testnet-api-key"
# export FIREBLOCKS_API_PRIVATE_KEY_PATH="/path/to/fireblocks_secret_testnet.key"
# export FIREBLOCKS_VAULT_ACCOUNT_IDS="0"
# export FIREBLOCKS_CHAIN_ID="9372"

# Contract Configuration
export SBT_NAME="TestSBT"
export SBT_ADMIN="0x..."
# ... other testnet settings
```

### 3. Create Symbolic Link

Create a symbolic link to the environment you want to use:

```bash
# Use testnet environment
ln -s .envrc.testnet .envrc

# Allow direnv to load it
direnv allow
```

## Switching Between Environments

To switch from one environment to another:

```bash
# Switch to testnet
ln -sf .envrc.testnet .envrc
direnv allow

# Switch to mainnet
ln -sf .envrc.mainnet .envrc
direnv allow
```

**Note:** The `-f` flag forces the creation of the new symbolic link, overwriting the existing one.

## Verifying Current Environment

Check which environment is currently active:

```bash
# Check the symbolic link target
ls -la .envrc

# Verify loaded environment variables
env | grep -E "^(RPC_URL|FIREBLOCKS_CHAIN_ID|SBT_)"
```

Expected output examples:

**Testnet:**
```
lrwxr-xr-x  1 user  staff  14 Oct 22 10:00 .envrc -> .envrc.testnet
RPC_URL=https://rpc.testnet.oasys.games
FIREBLOCKS_CHAIN_ID=9372
```

**Mainnet:**
```
lrwxr-xr-x  1 user  staff  14 Oct 22 10:00 .envrc -> .envrc.mainnet
RPC_URL=https://rpc.mainnet.oasys.games
FIREBLOCKS_CHAIN_ID=248
```

## Best Practices

### 1. Separate Fireblocks Configurations

Use different Fireblocks API keys and secret key files for each environment:

```
/secure/location/
├── fireblocks_secret.key          # Mainnet
└── fireblocks_secret_testnet.key  # Testnet
```

### 2. Different Vault Accounts

Use separate Fireblocks vault accounts for mainnet and testnet:

```bash
# .envrc.mainnet
export FIREBLOCKS_VAULT_ACCOUNT_IDS="0"  # Production vault

# .envrc.testnet
export FIREBLOCKS_VAULT_ACCOUNT_IDS="1"  # Testing vault
```

### 3. Clear Naming Conventions

Use clear names for contracts to distinguish environments:

```bash
# .envrc.mainnet
export SBT_NAME="MyGame Card"
export SBT_SYMBOL="MGC"

# .envrc.testnet
export SBT_NAME="MyGame Card Testnet"
export SBT_SYMBOL="MGCT"
```

### 4. Never Commit Environment Files

The `.gitignore` file is configured to exclude:
- `.envrc` (symbolic link)
- `.envrc.mainnet` (your configuration)
- `.envrc.testnet` (your configuration)
- `fireblocks_secret*.key` (Fireblocks secret keys)

Only the sample files are tracked in git.

### 5. Backup Your Configurations

Since environment files are not in git, backup them securely:

```bash
# Create encrypted backup
tar czf envrc-backup.tar.gz .envrc.mainnet .envrc.testnet
gpg --encrypt --recipient your@email.com envrc-backup.tar.gz
```

## Troubleshooting

### "direnv: error .envrc is blocked"

After creating or switching the symbolic link, you must allow direnv:

```bash
direnv allow
```

### Environment Variables Not Loading

1. Check the symbolic link:
   ```bash
   ls -la .envrc
   ```

2. Verify direnv is watching the directory:
   ```bash
   direnv status
   ```

3. Reload direnv:
   ```bash
   direnv reload
   ```

### Wrong Environment Being Used

Verify which file `.envrc` points to:

```bash
readlink .envrc
```

If it's wrong, recreate the symbolic link:

```bash
ln -sf .envrc.testnet .envrc
direnv allow
```

## Alternative: Environment Variable

If you prefer not to use symbolic links, you can create a wrapper script:

**deploy.sh:**

```bash
#!/bin/bash
set -e

ENV=${1:-testnet}

case $ENV in
  mainnet)
    source .envrc.mainnet
    ;;
  testnet)
    source .envrc.testnet
    ;;
  *)
    echo "Usage: $0 {mainnet|testnet}"
    exit 1
    ;;
esac

# Run deployment
forge script script/DeploySoulboundToken.s.sol:DeploySoulboundToken \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

Usage:

```bash
# Deploy to testnet
./deploy.sh testnet

# Deploy to mainnet
./deploy.sh mainnet
```

## Security Checklist

- [ ] Different Fireblocks API keys for mainnet and testnet
- [ ] Separate vault accounts for each environment
- [ ] Fireblocks secret key files are not in git
- [ ] `.envrc.mainnet` and `.envrc.testnet` are not in git
- [ ] Environment files are backed up securely
- [ ] Mainnet configuration uses Fireblocks (not private keys)
- [ ] Clear distinction between environment names (SBT_NAME, etc.)

## Additional Resources

- [direnv Documentation](https://direnv.net/)
- [Fireblocks Documentation](https://developers.fireblocks.com/)
- [Deployment Guide](./DEPLOYMENT.md)
