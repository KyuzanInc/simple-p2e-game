# Dependencies

This document describes the dependency management strategy for this project.

## Overview

This project uses **Foundry** for smart contract development, which manages dependencies via **git submodules**. All dependencies are locked to specific commit hashes to ensure build reproducibility.

## Current Dependencies

| Library | Version | Commit Hash | Purpose |
|---------|---------|-------------|---------|
| openzeppelin-contracts | v5.3.0 | `e4f70216d759d8e6a64144a9e1f7bbeed78e7079` | Core OpenZeppelin contracts |
| openzeppelin-contracts-upgradeable | v5.3.0 | `60b305a8f3ff0c7688f02ac470417b6bbf1c4d27` | Upgradeable versions of OZ contracts (proxy pattern support) |
| forge-std | v1.9.7 | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | Foundry standard library for testing |
| balancer-v2-monorepo | - | `4e01edc4ad8727b5e26fe764a4cce7ac1da99e14` | Balancer V2 interfaces and utilities |

## Version Locking Strategy

### Why Git Submodules?

Foundry uses git submodules to manage dependencies. This approach:
- ✅ Locks dependencies to exact commit hashes
- ✅ Ensures build reproducibility across environments
- ✅ Prevents unexpected breaking changes
- ✅ Makes audits more reliable

### How Versions are Locked

1. Each dependency is a git submodule in the `lib/` directory
2. The specific commit hash is stored in the git index
3. Running `git submodule update --init --recursive` checks out the exact commits
4. No version ranges (e.g., `^5.0.1`) are used

## Installing Dependencies

```bash
# Clone the repository
git clone <repository-url>

# Initialize and update all submodules
git submodule update --init --recursive

# Or use Foundry's install command
forge install
```

## Updating Dependencies

### Update to a Specific Version

```bash
# Method 1: Using forge update (updates to latest)
forge update lib/openzeppelin-contracts

# Method 2: Manual git checkout (recommended for version control)
cd lib/openzeppelin-contracts
git fetch --tags
git checkout v5.4.0  # Replace with desired version
cd ../..
git add lib/openzeppelin-contracts
git commit -m "chore: update OpenZeppelin to v5.4.0"
```

### Update All Dependencies

```bash
forge update
```

⚠️ **Warning**: Always review changes and run tests after updating dependencies.

## Verification

To verify the current versions:

```bash
# Check all submodule statuses
git submodule status

# Check specific library version
git -C lib/openzeppelin-contracts describe --tags --long
```

## Notes

- Dependencies are NOT managed via `package.json` (npm/yarn)
- The `foundry.toml` file contains dependency documentation in comments
- Always commit submodule updates separately from code changes
- After updating, run full test suite: `forge test -vvv`

## Related Files

- `.gitmodules`: Submodule configuration
- `foundry.toml`: Build configuration and dependency documentation
- `remappings.txt`: Import path remappings for Solidity
