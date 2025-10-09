# EIP-712 Signature Payload Specification

This document defines the EIP-712 typed structured data used for signature verification in the SBTSale contract.

## Overview

The SBTSale contract uses EIP-712 signatures to authorize purchases and free mints. All signatures must be generated using the domain separator and type hashes defined in this specification.

## Domain Separator

The EIP-712 domain separator is constructed with the following parameters:

```solidity
EIP712Domain(
    string name,
    string version,
    uint256 chainId,
    address verifyingContract
)
```

### Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `name` | `"SBTSale"` | Contract name for EIP-712 domain |
| `version` | `"1"` | Version identifier for the signature scheme |
| `chainId` | Dynamic | Chain ID where the contract is deployed (e.g., 248 for Oasys Hub-Layer) |
| `verifyingContract` | Dynamic | Address of the deployed SBTSale proxy contract |

## Signature Types

### 1. PurchaseOrder

Used for paid purchases of SBTs with signature authorization.

#### Type Hash

```solidity
keccak256("PurchaseOrder(uint256 purchaseId,address buyer,uint256[] tokenIds,address paymentToken,uint256 amount,uint256 minRevenueOAS,uint256 deadline)")
```

#### Struct Definition

```solidity
struct PurchaseOrder {
    uint256 purchaseId;      // Globally unique purchase ID for replay protection
    address buyer;           // Address of the authorized buyer (must match msg.sender)
    uint256[] tokenIds;      // Array of token IDs to be minted
    address paymentToken;    // Token address for payment (0x0 for native OAS, or ERC20 address)
    uint256 amount;          // Total payment amount including slippage tolerance (calculated off-chain)
    uint256 minRevenueOAS;   // Minimum OAS revenue that revenueRecipient should receive
    uint256 deadline;        // Signature expiration timestamp (block.timestamp)
}
```

#### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `purchaseId` | `uint256` | Globally unique identifier for this purchase. Used for replay protection. Must never be reused. |
| `buyer` | `address` | Address authorized to execute this purchase. Must match `msg.sender` in the transaction. |
| `tokenIds` | `uint256[]` | Array of specific token IDs to be minted from the SBT contract. Order does not matter but IDs must be unique. |
| `paymentToken` | `address` | Token used for payment:<br>- `0x0000000000000000000000000000000000000000` for native OAS<br>- Contract address for POAS<br>- Contract address for SMP |
| `amount` | `uint256` | Total payment amount in the specified token. This amount is calculated off-chain and includes slippage tolerance. For example, if the base price is 100 tokens and 5% slippage is desired, set `amount = 105`. |
| `minRevenueOAS` | `uint256` | Minimum amount of OAS (in wei) that the revenue recipient must receive after all swaps and distributions. If the actual revenue falls below this threshold, the transaction reverts with `InsufficientRevenue`. |
| `deadline` | `uint256` | Unix timestamp (seconds since epoch) after which this signature expires. Recommended to set a reasonable expiration (e.g., 1 hour from signature generation). |

#### Encoding for Signature

When encoding the `tokenIds` array, use:

```solidity
bytes32 tokenIdsHash = keccak256(abi.encode(order.tokenIds));
```

Then construct the struct hash:

```solidity
bytes32 structHash = keccak256(
    abi.encode(
        PURCHASE_ORDER_TYPEHASH,
        order.purchaseId,
        order.buyer,
        tokenIdsHash,  // Note: hashed array
        order.paymentToken,
        order.amount,
        order.minRevenueOAS,
        order.deadline
    )
);
```

### 2. FreePurchaseOrder

Used for free mints of SBTs with signature authorization (no payment required).

#### Type Hash

```solidity
keccak256("FreePurchaseOrder(uint256 purchaseId,address buyer,uint256[] tokenIds,uint256 deadline)")
```

#### Struct Definition

```solidity
struct FreePurchaseOrder {
    uint256 purchaseId;      // Globally unique purchase ID for replay protection
    address buyer;           // Address of the authorized buyer (must match msg.sender)
    uint256[] tokenIds;      // Array of token IDs to be minted
    uint256 deadline;        // Signature expiration timestamp (block.timestamp)
}
```

#### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `purchaseId` | `uint256` | Globally unique identifier for this free purchase. Used for replay protection. Must never be reused. |
| `buyer` | `address` | Address authorized to execute this free purchase. Must match `msg.sender` in the transaction. |
| `tokenIds` | `uint256[]` | Array of specific token IDs to be minted from the SBT contract. Order does not matter but IDs must be unique. |
| `deadline` | `uint256` | Unix timestamp (seconds since epoch) after which this signature expires. |

#### Encoding for Signature

Similar to PurchaseOrder, hash the tokenIds array:

```solidity
bytes32 tokenIdsHash = keccak256(abi.encode(order.tokenIds));

bytes32 structHash = keccak256(
    abi.encode(
        FREE_PURCHASE_ORDER_TYPEHASH,
        order.purchaseId,
        order.buyer,
        tokenIdsHash,  // Note: hashed array
        order.deadline
    )
);
```

## Complete Signature Generation

### Step-by-Step Process

1. **Construct the Domain Separator**
   ```solidity
   bytes32 domainSeparator = keccak256(
       abi.encode(
           keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
           keccak256(bytes("SBTSale")),
           keccak256(bytes("1")),
           block.chainid,
           address(sbtSaleContract)
       )
   );
   ```

2. **Construct the Struct Hash** (as shown above for each order type)

3. **Compute the EIP-712 Digest**
   ```solidity
   bytes32 digest = keccak256(
       abi.encodePacked(
           "\x19\x01",
           domainSeparator,
           structHash
       )
   );
   ```

4. **Sign the Digest**
   - Use ECDSA to sign the digest with the authorized signer's private key
   - The resulting signature should be in compact format (65 bytes: r, s, v)

5. **Submit the Signature**
   - Pass the signature bytes to the `purchase()` or `freePurchase()` function
   - The contract will verify using `SignatureChecker.isValidSignatureNow()`

## Security Considerations

### Replay Protection

- Each `purchaseId` can only be used once
- The contract maintains a mapping of used purchase IDs
- Attempting to reuse a purchase ID will revert with `PurchaseIdAlreadyUsed`

### Expiration

- All signatures include a `deadline` field
- Transactions submitted after the deadline will revert with `ExpiredDeadline`
- Recommended to set reasonable expiration times (e.g., 1 hour)

### Signer Authorization

- Only signatures from the authorized signer address are accepted
- The signer address can be updated by the contract owner using `setSigner()`
- Signatures are verified using OpenZeppelin's `SignatureChecker` which supports both EOA and ERC-1271 smart contract wallets

### Buyer Verification

- The `buyer` field must match `msg.sender`
- This prevents signature front-running or unauthorized use of valid signatures
- Attempting to use a signature for a different buyer will revert with `BuyerMismatch`

## Off-Chain Signature Generation Example

### JavaScript/TypeScript (ethers.js v6)

```typescript
import { ethers } from 'ethers';

// Define the domain
const domain = {
    name: 'SBTSale',
    version: '1',
    chainId: 248, // Oasys Hub-Layer
    verifyingContract: '0x...' // SBTSale contract address
};

// Define the PurchaseOrder type
const purchaseOrderTypes = {
    PurchaseOrder: [
        { name: 'purchaseId', type: 'uint256' },
        { name: 'buyer', type: 'address' },
        { name: 'tokenIds', type: 'uint256[]' },
        { name: 'paymentToken', type: 'address' },
        { name: 'amount', type: 'uint256' },
        { name: 'minRevenueOAS', type: 'uint256' },
        { name: 'deadline', type: 'uint256' }
    ]
};

// Create the order
const order = {
    purchaseId: 12345,
    buyer: '0x...',
    tokenIds: [1, 2, 3],
    paymentToken: '0x0000000000000000000000000000000000000000', // Native OAS
    amount: ethers.parseEther('1.05'), // 1 OAS + 5% slippage
    minRevenueOAS: ethers.parseEther('0.1'), // Minimum 0.1 OAS revenue
    deadline: Math.floor(Date.now() / 1000) + 3600 // 1 hour from now
};

// Sign the order
const signer = new ethers.Wallet('0x...'); // Authorized signer's private key
const signature = await signer.signTypedData(domain, purchaseOrderTypes, order);
```

### Python (web3.py)

```python
from eth_account.messages import encode_structured_data
from eth_account import Account

# Define the domain
domain_data = {
    'name': 'SBTSale',
    'version': '1',
    'chainId': 248,
    'verifyingContract': '0x...'
}

# Define the message types
message_types = {
    'EIP712Domain': [
        {'name': 'name', 'type': 'string'},
        {'name': 'version', 'type': 'string'},
        {'name': 'chainId', 'type': 'uint256'},
        {'name': 'verifyingContract', 'type': 'address'}
    ],
    'PurchaseOrder': [
        {'name': 'purchaseId', 'type': 'uint256'},
        {'name': 'buyer', 'type': 'address'},
        {'name': 'tokenIds', 'type': 'uint256[]'},
        {'name': 'paymentToken', 'type': 'address'},
        {'name': 'amount', 'type': 'uint256'},
        {'name': 'minRevenueOAS', 'type': 'uint256'},
        {'name': 'deadline', 'type': 'uint256'}
    ]
}

# Create the order
order_data = {
    'purchaseId': 12345,
    'buyer': '0x...',
    'tokenIds': [1, 2, 3],
    'paymentToken': '0x0000000000000000000000000000000000000000',
    'amount': 1050000000000000000,  # 1.05 OAS in wei
    'minRevenueOAS': 100000000000000000,  # 0.1 OAS in wei
    'deadline': int(time.time()) + 3600
}

# Create the structured data
structured_data = {
    'types': message_types,
    'primaryType': 'PurchaseOrder',
    'domain': domain_data,
    'message': order_data
}

# Sign
private_key = '0x...'  # Authorized signer's private key
signable_message = encode_structured_data(structured_data)
signed = Account.sign_message(signable_message, private_key)
signature = signed.signature.hex()
```

## Testing Signatures

When testing signature verification:

1. Use a known private key for the signer
2. Generate signatures using the exact domain and type definitions shown above
3. Verify the `getSigner()` function returns the correct address
4. Test expiration by setting `deadline` in the past
5. Test replay protection by attempting to reuse a `purchaseId`
6. Test buyer verification by signing for one address but calling from another

## References

- [EIP-712: Typed structured data hashing and signing](https://eips.ethereum.org/EIPS/eip-712)
- [OpenZeppelin SignatureChecker](https://docs.openzeppelin.com/contracts/4.x/api/utils#SignatureChecker)
- [ERC-1271: Standard Signature Validation Method for Contracts](https://eips.ethereum.org/EIPS/eip-1271)
