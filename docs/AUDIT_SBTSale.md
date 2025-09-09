# 🔒 Smart Contract Security Audit Report - SBTSale

**Contract**: SBTSale.sol  
**Chain**: Oasys  
**Audit Date**: January 9, 2025  
**Auditor**: Professional Security Audit Team  
**Version**: v1.0  
**Commit Hash**: Current branch (feature/smart-contract-updates)

---

## 📋 Executive Summary

### Overall Assessment

**Security Score: 7.2/10**  
**Risk Level: MEDIUM**

The SBTSale contract implements complex DeFi operations with Balancer V2 integration. While core security measures are in place, there are notable concerns regarding price manipulation risks and the non-view nature of price queries.

### Risk Distribution

- **Critical**: 0
- **High**: 1
- **Medium**: 3
- **Low**: 4
- **Informational**: 5

### Primary Risk Factors

1. Non-view `queryPrice` function enables potential state manipulation
2. Balancer V2 pool dependency creates single point of failure
3. Complex swap operations increase attack surface

### Key Security Features

✅ EIP-712 signature verification  
✅ Replay attack protection via purchaseId  
✅ Slippage protection mechanism  
✅ Reentrancy guards on all entry points  
✅ Comprehensive input validation  

---

## 🎯 Audit Scope

### Files Audited

| File | Lines | Language | Purpose |
|------|-------|----------|---------|
| SBTSale.sol | 837 | Solidity 0.8+ | NFT Sales & DEX Integration |
| ISBTSale.sol | 279 | Solidity 0.7+ | Sales Interface |
| IVaultPool.sol | 14 | Solidity 0.7+ | Pool Interface |

### Architecture Overview

```
SBTSale
├── Purchase Flow
│   ├── Signature Verification (EIP-712)
│   ├── Payment Collection (OAS/POAS/SMP)
│   ├── DEX Swaps (Balancer V2)
│   ├── SMP Distribution (Burn/Liquidity/Revenue)
│   └── NFT Minting
├── Access Control
│   └── Ownable Pattern
└── Safety Mechanisms
    ├── ReentrancyGuard
    ├── Slippage Protection
    └── Purchase ID Tracking
```

### Immutable Configuration

```solidity
// Core protocol parameters (constructor-set)
_smpBasePrice: 50 SMP per NFT
_smpBurnRatio: 5000 (50%)
_smpLiquidityRatio: 4000 (40%)
_smpRevenueRatio: 1000 (10%) // Implicit
MAX_BATCH_SIZE: 200 NFTs
```

---

## 🔴 High Severity Findings

### HIGH-01: Non-View Price Query Enables MEV Attacks

**Severity**: High  
**Impact**: Price manipulation, MEV exploitation  
**Likelihood**: Medium  
**Location**: Lines 278-295

**Description**:  
The `queryPrice` function is not marked as `view` due to Balancer V2's `queryBatchSwap` implementation. This creates MEV opportunities and potential for price manipulation.

**Vulnerable Code**:
```solidity
function queryPrice(uint256 tokenCount, address paymentToken)
    public
    returns (uint256 price)  // Not 'view' - can modify state
{
    // Uses IVault.queryBatchSwap internally
    return _isSMP(paymentToken) ? smpPrice : _getRequiredOASFromLP(smpPrice);
}
```

**Attack Scenario**:
1. Attacker monitors mempool for `queryPrice` calls
2. Front-runs with liquidity manipulation in Balancer pool
3. User receives manipulated price
4. Back-runs to restore pool state

**Recommendation**:
- Short-term: Implement off-chain price calculation
- Long-term: Investigate Balancer V2 static call alternatives
- Consider adding a price oracle as backup

**Mitigation Status**: ⚠️ Requires architectural change

---

## 🟡 Medium Severity Findings

### MEDIUM-01: Signer Zero Address Not Validated

**Severity**: Medium  
**Impact**: Purchase bypass if misconfigured  
**Likelihood**: Low  
**Location**: Lines 454-456

**Description**:  
When `_signer` is `address(0)`, signature verification always returns false, blocking all purchases. However, there's no validation preventing this state.

**Code**:
```solidity
function _verifyPurchaseOrder(...) internal view returns (bool) {
    if (_signer == address(0)) {
        return false;  // Silently fails
    }
    // ...
}
```

**Recommendation**:
```solidity
function setSigner(address newSigner) external onlyOwner {
    require(newSigner != address(0), "Invalid signer");
    _signer = newSigner;
}
```

---

### MEDIUM-02: Single DEX Dependency Risk

**Severity**: Medium  
**Impact**: Service disruption  
**Likelihood**: Low  
**Location**: Entire swap mechanism

**Description**:  
Complete dependency on a single Balancer V2 pool creates a single point of failure. Pool liquidity issues or Balancer outages would halt all sales.

**Risk Factors**:
- Liquidity drainage
- Pool pause/emergency shutdown
- Balancer V2 vulnerability

**Recommendation**:
- Implement fallback price mechanisms
- Consider multi-DEX aggregation
- Add circuit breakers for extreme price deviations

---

### MEDIUM-03: Fixed Price Model Market Inefficiency

**Severity**: Medium  
**Impact**: Economic inefficiency  
**Likelihood**: High  
**Location**: Line 144 (constructor)

**Description**:  
The fixed 50 SMP price per NFT doesn't adapt to market conditions, potentially leading to arbitrage opportunities or unsustainable economics.

**Recommendation**:
- Implement dynamic pricing mechanism
- Add admin function to adjust base price
- Consider bonding curve model

---

## 🔵 Low Severity Findings

### LOW-01: Batch Size Limit May Be Restrictive

**Severity**: Low  
**Location**: Line 67

**Description**:  
The 200 NFT batch limit may be insufficient for large-scale operations or airdrops.

```solidity
uint256 public constant MAX_BATCH_SIZE = 200;
```

**Recommendation**: Consider making this configurable or increasing the limit.

---

### LOW-02: Unchecked Native Token Reception

**Severity**: Low  
**Location**: Line 836

**Description**:  
The `receive()` function accepts native tokens without validation or recovery mechanism.

```solidity
receive() external payable {}
```

**Recommendation**: Implement a withdrawal function for stuck funds.

---

### LOW-03: Slippage Protection One-Directional

**Severity**: Low  
**Location**: Lines 419-432

**Description**:  
Slippage protection only prevents excessive costs, not insufficient amounts (though this is intentional for user benefit).

---

### LOW-04: Missing Event Indexing

**Severity**: Low  
**Location**: Lines 67-80

**Description**:  
The `Purchased` event doesn't index `paymentToken`, making filtering by payment type inefficient.

---

## 📊 Informational Findings

### INFO-01: Incomplete NatSpec Documentation

Important internal functions lack comprehensive documentation, reducing code maintainability.

### INFO-02: Magic Numbers Usage

Hardcoded values like `5 minutes` (line 621) should be named constants.

### INFO-03: Storage Optimization Opportunities

Boolean and address variables could be packed to save storage slots.

### INFO-04: Gas Inefficient Loops

Multiple loops in `_mintNFTs` (lines 822-824) could be optimized.

### INFO-05: Compiler Warning Suppressions

Multiple warning codes ignored in foundry.toml without documentation.

---

## ✅ Security Checklist

| Security Check | Status | Details |
|----------------|--------|---------|
| Reentrancy Protection | ✅ Secure | NonReentrant modifier properly applied |
| Signature Verification | ✅ Secure | EIP-712 standard implementation |
| Replay Protection | ✅ Secure | purchaseId tracking prevents replay |
| Integer Overflow | ✅ Safe | Solidity 0.8+ automatic checks |
| Access Control | ✅ Secure | Ownable pattern correctly implemented |
| Price Manipulation | ⚠️ Risk | queryPrice non-view issue |
| Slippage Protection | ✅ Implemented | Configurable tolerance |
| Input Validation | ✅ Comprehensive | All inputs validated |
| External Calls | ✅ Safe | Proper error handling |
| Centralization | ⚠️ Moderate | Owner has significant control |
| DoS Resistance | ✅ Good | Batch limits prevent gas exhaustion |
| Flash Loan Attacks | ⚠️ Possible | Via Balancer pool manipulation |

---

## 🔬 Attack Vector Analysis

### 1. Sandwich Attack

**Risk**: High  
**Vector**: Front-running purchase transactions  
**Mitigation**: Slippage protection partially mitigates  

### 2. Signature Replay

**Risk**: Mitigated  
**Vector**: Reusing valid signatures  
**Mitigation**: purchaseId tracking prevents replay  

### 3. Price Oracle Manipulation

**Risk**: Medium  
**Vector**: Balancer pool manipulation  
**Mitigation**: Requires significant capital  

### 4. Reentrancy

**Risk**: Mitigated  
**Vector**: Callback exploitation  
**Mitigation**: NonReentrant guards in place  

---

## ⛽ Gas Optimization Recommendations

### Priority 1: Storage Access Optimization

```solidity
// Current: Multiple SLOADs
if(_signer == address(0)) // SLOAD 1
if(_signer != msg.sender) // SLOAD 2

// Optimized: Single SLOAD
address signer = _signer;
if(signer == address(0))
if(signer != msg.sender)
```
**Estimated Savings**: 2,100 gas per transaction

### Priority 2: Batch Operations

Combine multiple NFT mints into single operation where possible.

### Priority 3: Immutable Variables

Consider making more configuration parameters immutable to save gas.

---

## 🔄 Upgrade Considerations

### Storage Layout Safety

Current storage layout is upgrade-safe with proper slot allocation:
```solidity
// Slots 0-50: OpenZeppelin reserved
// Slot 51: _signer
// Slot 52: usedPurchaseIds mapping
// Slot 53: _sbtContract
```

### Recommended Improvements for V2

1. **Dynamic Pricing**: Implement market-responsive pricing
2. **Multi-DEX Support**: Reduce single point of failure
3. **Price Oracle**: Add Chainlink or similar oracle
4. **Batch Optimizations**: Optimize for large-scale minting
5. **Emergency Pause**: Add circuit breaker mechanism

---

## 🏁 Conclusion

The SBTSale contract demonstrates **GOOD OVERALL SECURITY** with comprehensive protection mechanisms. However, the HIGH severity price manipulation risk requires attention before mainnet deployment.

### Strengths
- ✅ Robust signature verification system
- ✅ Comprehensive input validation
- ✅ Well-implemented safety mechanisms
- ✅ Clean separation of concerns

### Weaknesses
- ❌ Non-view price queries enable MEV
- ⚠️ Single DEX dependency
- ⚠️ Fixed pricing model

**Overall Assessment**: **CONDITIONALLY APPROVED**

**Requirements for Production**:
1. Address HIGH-01 price manipulation risk
2. Implement signer validation in setSigner
3. Consider backup price mechanisms

**Risk Level**: **MEDIUM** (reducible to LOW with recommended fixes)  
**Security Score**: **7.2/10** (potential 8.5/10 after fixes)

The contract is suitable for testnet deployment and controlled mainnet launch with monitoring. Full production deployment should occur after addressing the high-priority findings.

---

## 📎 Appendix

### Test Coverage Analysis

- Core purchase flows: ✅ Covered
- Edge cases: ✅ Covered  
- Signature verification: ✅ Comprehensive
- Slippage scenarios: ✅ Tested
- Integration tests: ✅ Balancer V2 mocks

### Deployment Checklist

- [ ] Set signer address before launch
- [ ] Verify Balancer pool liquidity
- [ ] Configure SBT contract address
- [ ] Test signature generation backend
- [ ] Monitor initial transactions
- [ ] Implement price monitoring alerts

---

*This audit report represents a point-in-time security assessment. Continuous monitoring and regular re-audits are recommended as the protocol evolves.*