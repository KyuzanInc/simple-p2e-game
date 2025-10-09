# Audit Fixes Plan

## Overview

This document outlines the comprehensive plan for addressing all findings from the Quantstamp audit report (September 30, 2025), including issues KYU-1 through KYU-4 and S1 through S5. Each fix is implemented as an independent commit on the `audit-fixes` branch.

---

## Scope

- **Target Repository**: `KyuzanInc/simple-p2e-game`
- **Target Files**: Primarily `SBTSale.sol`, `SoulboundToken.sol`, `ISBTSale.sol`
- **Objective**: Enhance contract security, reliability, and maintainability to meet re-audit standards

---

## KYU-1: Effective Slippage Control (Medium)

### Problem

The `_validateSlippage()` function was effectively non-functional. Additionally, `_swapSMPtoOASForRevenueRecipient()` lacked `minOut` constraints, potentially allowing unfavorable price execution in low-liquidity conditions. Furthermore, `_provideLiquidity()` set `minBPT = 0`, providing no lower bound on BPT tokens received.

### Solution (Following Quantstamp Recommendations)

1. **Signature Payload Changes**
   - Remove `maxSlippageBps` parameter
   - Add `minRevenueOAS` parameter (minimum OAS amount for revenue recipient)
   - Calculate `amount` off-chain including slippage (e.g., for expected value x with 5% tolerance: `amount = x * 1.05`)

2. **Remove `_validateSlippage()`**
   - No longer needed as slippage is included in off-chain `amount` calculation

3. **Improve `_swapSMPtoOASForRevenueRecipient()`**
   - Accept `minRevenueOAS` as parameter
   - Enforce `revenueOAS >= minRevenueOAS` as mandatory condition

4. **Improve `_provideLiquidity()`**
   - Ensure received BPT is always `> 0`

### Commit

- `feat: implement effective slippage control with off-chain calculation and minRevenueOAS`

### Test Coverage

- Revert when `minRevenueOAS` is not met
- Revert when BPT = 0 in liquidity provision
- Normal operation executes at expected price range
- Signature verification works correctly with new payload structure

---

## KYU-2: Safer Ownership Transfer (Low)

### Problem

`transferOwnership` completes in a single transaction, creating risk of irrecoverable ownership loss if an incorrect address is specified.

### Solution

Replace `OwnableUpgradeable` with `Ownable2StepUpgradeable` to implement two-step ownership transfer. After calling `transferOwnership(newOwner)`, the transfer is only finalized when `acceptOwnership()` is called.

### Commit

- `refactor: migrate to Ownable2StepUpgradeable for safer ownership transfer`

### Test Coverage

- Old owner remains valid after `transferOwnership`
- New owner is successfully transferred via `acceptOwnership`
- Invalid or duplicate address reverts appropriately

---

## KYU-3: Prevent Ownership Renunciation (Low)

### Problem

`renounceOwnership()` can be executed directly, risking contract becoming unmanageable through accidental execution.

### Solution

1. Define custom error `OwnershipCannotBeRenounced()` in `ISBTSale.sol`
2. Override `renounceOwnership()` in `SBTSale.sol` to always revert with custom error
3. Maintain consistency with other errors and improve gas efficiency

This prevents accidental contract abandonment.

### Commit

- `fix: disable renounceOwnership to avoid accidental loss of control`

### Test Coverage

- `renounceOwnership()` reverts with `OwnershipCannotBeRenounced` error
- Non-owner calls also revert appropriately

---

## KYU-4: Enhanced Interface Support for SoulboundToken (Undetermined)

### Problem

`SoulboundToken`'s `supportsInterface()` did not support `ISBTSaleERC721`, making type validation in `SBTSale.setSBTContract()` incomplete.

### Solution

1. Add `if (interfaceId == type(ISBTSaleERC721).interfaceId) return true;` to `SoulboundToken.supportsInterface()`
2. Add `supportsInterface` check to `SBTSale.setSBTContract()` to reject non-compliant implementations

### Commit

- `fix: add ISBTSaleERC721 to supportsInterface and enforce validation in SBTSale`

### Test Coverage

- Only contracts implementing correct interface pass validation
- Fake implementations are rejected

---

## S1: Documentation Enhancement (Info)

### Problem

Insufficient documentation for storage variables and functions, making specification understanding and maintenance difficult.

### Solution

Add NatSpec comments to all public/external functions. Document EIP-712 signature payload structure in `/docs/contracts/payload.md`.

### Commit

- `docs: add full NatSpec and payload specification`

---

## S2: Enriched Error Messages (Info)

### Problem

Current error messages are too simple, making transaction failure analysis difficult.

### Solution

Add parameters to custom errors to return specific values on failure:

```solidity
error InvalidRecipient(address recipient);
error InsufficientRevenue(uint256 minRequired, uint256 actual);
error InsufficientBPTReceived(uint256 received);
```

Include old/new values in key setter events for better monitoring.

### Commit

- `feat: enrich custom errors and events with contextual data`

---

## S3: Existence Check for mintTimeOf() (Info)

### Problem

Calling `mintTimeOf()` for non-existent token IDs does not revert, potentially returning incorrect values.

### Solution

Add the following check:

```solidity
require(_exists(tokenId), "Token does not exist");
```

### Commit

- `fix: add existence check to mintTimeOf()`

---

## S4: Lock OpenZeppelin Version (Info)

### Problem

OZ libraries specified with range like `^5.0.1` risk incorporating breaking changes in the future.

### Solution

Lock dependencies to ensure build reproducibility:

- Change `openzeppelin` dependency in `package.json` to `=5.0.1`
- Explicitly fix library versions in `foundry.toml`

### Commit

- `chore: lock OZ version to ensure stability`

---

## S5: General Improvements & Refactoring (Info)

### Problem

Multiple minor issues including redundant processing, duplicate checks, and missing events exist in the code.

### S5.1: Remove `buyer` Argument

- **Target**: `purchase()` function
- **Change**: Remove `buyer` argument, use `msg.sender` consistently
- **Reason**: No need to accept as parameter; should always use `msg.sender`

### S5.2: `deadline` Parameter in `_swap`

- **Target**: `_swap()` function
- **Change**: Remove or make `deadline` effective (consider TWAP integration)
- **Reason**: Currently unused or not properly configured

### S5.3: Remove Duplicate Checks in `_getTotalSMPPrice()`

- **Target**: `_getTotalSMPPrice()` function
- **Change**: Remove redundant validation logic
- **Reason**: Same checks already performed elsewhere

### S5.4: Remove Redundant Check in `_payWithSwapToSMP()`

- **Target**: `_payWithSwapToSMP()` function
- **Change**: Remove `if (actualOut != requiredSMP)` check
- **Reason**: Already validated inside `_swap()`

### S5.5: Add Event to `setBaseURI()`

- **Target**: `SoulboundToken.setBaseURI()` function
- **Change**: Add `BaseURIUpdated(old, new)` event
- **Reason**: Enable monitoring of important state changes

### S5.6: Empty String Check for `setBaseURI()`

- **Target**: `SoulboundToken.setBaseURI()` function
- **Change**: Add validation to reject empty strings
- **Reason**: Prevent invalid baseURI configuration

### S5.7: Same-Value Checks in Setters

- **Target**: `setSigner()`, `setSBTContract()` functions
- **Change**: Make no-op when same value is set
- **Reason**: Prevent unnecessary event emission and gas consumption

### S5.8: Eliminate Magic Values (Already Completed)

- **Target**: Locations using interface IDs
- **Change**: Use `type(IFace).interfaceId` to eliminate magic values
- **Reason**: Improve code readability and maintainability
- **Status**: ✅ Already completed (using `type(ISBTSaleERC721).interfaceId` in `setSBTContract()`)

### S5.9: Refactor `_isPOAS()` / `_isSMP()`

- **Target**: `_isPOAS()`, `_isSMP()` functions
- **Change**: Depend on `getPOAS()` / `getSMP()` to reduce code duplication
- **Reason**: Follow DRY principle

### S5.10: Optimize `_getPoolAssets()`

- **Target**: `_getPoolAssets()` function
- **Change**: Store result in immutable variable
- **Reason**: Reduce gas costs

### Commits

Individual or grouped commits for related changes:
- `refactor: remove buyer argument and use msg.sender` (S5.1)
- `refactor: handle deadline in _swap` (S5.2)
- `refactor: remove redundant checks` (S5.3, S5.4)
- `feat: add BaseURIUpdated event and validation` (S5.5, S5.6)
- `refactor: add no-op checks to setters` (S5.7)
- ~~`refactor: use type().interfaceId instead of magic values` (S5.8)~~ → Skipped (already completed)
- `refactor: reduce code duplication in token checks` (S5.9)
- `refactor: optimize _getPoolAssets with immutable` (S5.10)

---

## Test Enhancement

Target: Branch Coverage 85%+, Line Coverage 95%+

Test additions include:

- Slippage control (revert on `minRevenueOAS` not met, revert on BPT = 0)
- Ownership transfer and renounce prevention
- `ISBTSaleERC721` compliance checks
- `mintTimeOf()` revert confirmation
- Verification with new signature payload structure

### Commit

- `test: add boundary and negative case coverage`

---

## Release

Final steps:

1. Add "Audit Fixes Completed" to `CHANGELOG.md`
2. Place audit response summary in `/docs/audit/`
3. Request re-audit from Quantstamp as needed

### Commit

- `chore: finalize audit fixes and update changelog`
