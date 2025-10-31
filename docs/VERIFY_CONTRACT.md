# Contract Verification Guide

This guide explains how to verify deployed contracts for the simple-p2e-game project on the Oasys explorers. The explorer infrastructure is powered by Blockscout, so the verification flow uses Foundry's Blockscout integration.

## Prerequisites

- Foundry installed (`forge`, `cast`, `anvil`)
- Contracts compiled with the same configuration used for deployment (matching `foundry.toml`)
- Deployed contract addresses and constructor arguments
- Environment variables configured via `.envrc.testnet` or `.envrc.mainnet`
- RPC endpoint reachable from the machine running `forge`

## Environment Reference

| Network | Chain ID | `RPC_URL` Environment Value       | `EXPLORER_API_URL` Environment Value        |
| ------- | -------- | --------------------------------- | ------------------------------------------- |
| Mainnet | 248      | `https://rpc.mainnet.oasys.games` | `https://explorer.oasys.games/api/`         |
| Testnet | 9372     | `https://rpc.testnet.oasys.games` | `https://explorer.testnet.oasys.games/api/` |

> **Note:** The explorer API URL must include the trailing `/api/`.

## Shared Setup

1. Switch to the target environment:
   ```bash
   npm run env:switch:mainnet   # or env:switch:testnet
   ```
2. Confirm the required variables are loaded:
   ```bash
   npm run env:status
   env | grep -E "^(RPC_URL|EXPLORER_API_URL|SBT_|P2E_)"
   ```

All subsequent commands rely on environment variables defined in `.envrc.*` such as `$RPC_URL`, `$EXPLORER_API_URL`, `$SBT_PROXY`, `$SBT_IMPLEMENTATION`, `$SBTSALE_PROXY`, and `$SBTSALE_IMPLEMENTATION`.

## SoulboundToken Verification

1. Confirm the implementation address stored in `.envrc.*`:
   ```bash
   echo "SoulboundToken implementation: $SBT_IMPLEMENTATION"
   ```
   > If the environment variable is not populated yet, derive it with:
   >
   > ```bash
   > IMPLEMENTATION_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
   > SBT_IMPLEMENTATION=$(cast --to-address $(cast storage $SBT_PROXY $IMPLEMENTATION_SLOT --rpc-url $RPC_URL))
   > ```
2. Verify the implementation contract:
   ```bash
   forge verify-contract \
     --rpc-url $RPC_URL \
     --verifier blockscout \
     --verifier-url $EXPLORER_API_URL \
     --watch \
     $SBT_IMPLEMENTATION \
     src/SoulboundToken.sol:SoulboundToken
   ```
   - To pin the compiler version and optimization runs (if they differ from defaults):
     ```bash
     forge verify-contract \
       --rpc-url $RPC_URL \
       --verifier blockscout \
       --verifier-url $EXPLORER_API_URL \
       --compiler-version 0.8.26 \
       --num-of-optimizations 200 \
       --watch \
       $SBT_IMPLEMENTATION \
       src/SoulboundToken.sol:SoulboundToken
     ```

## SBTSale Verification

1. Confirm the implementation address stored in `.envrc.*`:
   ```bash
   echo "SBTSale implementation: $SBTSALE_IMPLEMENTATION"
   ```
   > If the environment variable is not populated yet, derive it with:
   >
   > ```bash
   > IMPLEMENTATION_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
   > SBTSALE_IMPLEMENTATION=$(cast --to-address $(cast storage $SBTSALE_PROXY $IMPLEMENTATION_SLOT --rpc-url $RPC_URL))
   > ```
2. Verify the implementation contract:

   ```bash
   SBTSALE_CONSTRUCTOR_ARGS=$(cast abi-encode \
     "constructor(address,address,address,address,uint256,uint256,uint256)" \
     $P2E_POAS_MINTER \
     $P2E_LIQUIDITY_POOL \
     $P2E_LP_RECIPIENT \
     $P2E_REVENUE_RECIPIENT \
     $P2E_SMP_BASE_PRICE \
     $P2E_SMP_BURN_RATIO \
     $P2E_SMP_LIQUIDITY_RATIO)

   forge verify-contract \
     --rpc-url $RPC_URL \
     --verifier blockscout \
     --verifier-url $EXPLORER_API_URL \
     --constructor-args $SBTSALE_CONSTRUCTOR_ARGS \
     --watch \
     $SBTSALE_IMPLEMENTATION \
     src/SBTSale.sol:SBTSale
   ```

### Checking Verification Status

- Pass `--watch` to wait for Blockscout's asynchronous verification result.
- Open the explorer UI and confirm that the contract shows a verified status (green check).

## Troubleshooting

- **Verification fails with “source code does not match”**  
  Rebuild the contracts and ensure the compiler version and optimizer runs match the deployment configuration. Provide explicit flags if needed.

- **Explorer returns network errors**  
  Make sure `--verifier-url` ends with `/api/` and that the RPC endpoint responds.

- **Constructor arguments mismatch**  
  Extract the creation bytecode with `cast code <ADDRESS>` or reuse deployment logs to rebuild the ABI-encoded arguments.

- **Nonce or transaction issues in Fireblocks flows**  
  Re-run with `--slow` and confirm approvals in the Fireblocks console before retrying verification.

## Additional Resources

- [Deployment Guide](./DEPLOYMENT.md)
- [Role Setup Guide](./SETUP_ROLES.md)
- [Foundry Book – forge verify-contract](https://book.getfoundry.sh/reference/forge/forge-verify-contract)
- [Oasys Documentation](https://docs.oasys.games/)
