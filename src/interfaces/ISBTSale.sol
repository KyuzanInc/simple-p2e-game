// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import {ISBTSaleERC721} from "./ISBTSaleERC721.sol";

/**
 * @title ISBTSale
 * @notice Contract for acquiring NFT assets by paying tokens.
 *
 * Basic Specifications
 * - Supports 3 payment token types:
 *   - Native OAS
 *   - POAS (contracts/interfaces/IPOAS.sol)
 *   - SMP (contracts/interfaces/ISMP.sol)
 * - Single payment method supports all token types
 * - SMP token requires a Balancer V2 compliant liquidity pool (LP) with WOAS
 *   Note: The pool uses WOAS-SMP pair, but Balancer V2 automatically handles native OAS conversion
 * - Multiple NFTs can be acquired in a single payment, but only one payment token type per transaction
 * - NFT pricing is based on SMP token with a current fixed price of 50 SMP
 *
 */
interface ISBTSale {
    // Signature verification structure for paid purchase EIP-712
    struct PurchaseOrder {
        uint256 purchaseId; // Globally unique purchase ID
        address buyer;
        uint256[] tokenIds;
        address paymentToken;
        uint256 amount; // Amount including slippage tolerance (calculated off-chain)
        uint256 minRevenueOAS; // Minimum OAS revenue that revenueRecipient should receive
        uint256 deadline;
    }

    // Signature verification structure for free purchase EIP-712
    struct FreePurchaseOrder {
        uint256 purchaseId; // Globally unique purchase ID
        address buyer;
        uint256[] tokenIds;
        uint256 deadline;
    }

    // Errors
    error InvalidPaymentToken(address token); // Invalid or unsupported payment token
    error InvalidRecipient(address recipient); // Invalid recipient address (zero address or other constraint violation)
    error InvalidPaymentAmount(uint256 amount); // Payment amount does not match expected value
    error InvalidProtocolValue(string parameter); // Invalid protocol parameter value
    error InvalidPool(); // Invalid liquidity pool configuration
    error InvalidAddress(address addr); // Invalid address provided
    error InvalidSwap(string message); // Swap operation failed with detailed message
    error NoItems(); // No items specified for operation
    error TooManyItems(uint256 count, uint256 maxAllowed); // Item count exceeds maximum allowed
    error ArrayLengthMismatch(uint256 length1, uint256 length2); // Array length mismatch between parameters
    error TransferFailed(address token, address to, uint256 amount); // Token transfer failed
    error InvalidSignature(); // Signature verification failed
    error ExpiredDeadline(uint256 deadline, uint256 currentTime); // Signature deadline has expired
    error PurchaseIdAlreadyUsed(uint256 purchaseId); // Purchase ID has already been used
    error InvalidSigner(address signer); // Signer address is invalid or not set
    error BuyerMismatch(address expected, address actual); // Buyer address does not match authorized buyer
    error InsufficientRevenue(uint256 minRequired, uint256 actual); // Revenue recipient would receive less than minimum
    error InsufficientBPTReceived(uint256 received); // Liquidity provision resulted in zero or insufficient BPT
    error OwnershipCannotBeRenounced(); // Ownership renouncement is disabled to prevent accidental loss of control

    // Events
    /// @dev Emitted when SBTs are purchased with complete protocol information
    /// @param buyer Address of the buyer
    /// @param tokenIds Array of token IDs minted
    /// @param paymentToken Token used for payment
    /// @param actualAmount Amount actually used for payment
    /// @param refundAmount Amount refunded to the buyer
    /// @param burnSMP Amount of SMP burned
    /// @param liquiditySMP Amount of SMP provided to liquidity pool
    /// @param revenueSMP Amount of SMP allocated for revenue
    /// @param revenueOAS Amount of OAS transferred to revenue recipient
    /// @param revenueRecipient Address receiving the OAS revenue
    /// @param lpRecipient Address receiving the LP tokens
    /// @param purchaseId Used purchase ID for replay protection
    event Purchased(
        address indexed buyer,
        uint256[] tokenIds,
        address paymentToken,
        uint256 actualAmount,
        uint256 refundAmount,
        uint256 burnSMP,
        uint256 liquiditySMP,
        uint256 revenueSMP,
        uint256 revenueOAS,
        address revenueRecipient,
        address lpRecipient,
        uint256 indexed purchaseId
    );

    /// @dev Emitted when signer address is updated
    /// @param oldSigner Previous signer address
    /// @param newSigner New signer address
    event SignerUpdated(address indexed oldSigner, address indexed newSigner);

    /// @dev Emitted when SBT contract address is updated
    /// @param oldSBTContract Previous SBT contract address
    /// @param newSBTContract New SBT contract address
    event SBTContractUpdated(address indexed oldSBTContract, address indexed newSBTContract);

    /// @dev Emitted when owner mints SBTs directly
    /// @param owner Address of the contract owner
    /// @param recipients Array of addresses receiving SBTs
    /// @param tokenIds Array of token IDs minted
    event OwnerMinted(address indexed owner, address[] recipients, uint256[] tokenIds);

    /**
     * @dev Query total required token amount for purchasing specified number of SBTs
     *
     * This method calculates the total payment amount needed for the specified number of SBTs:
     * - Takes the number of SBTs to purchase
     * - Takes the payment token address to be used
     * - For non-SMP tokens, queries the LP for the required token amount due to swap requirements
     *
     * Note: This method is not a 'view' function due to Balancer V2 design constraints.
     *       Therefore, callers must explicitly use `eth_call` to call it.
     *
     * @param tokenCount Number of SBTs to get pricing for
     * @param token Token address for payment (native OAS: 0x0, POAS, or SMP)
     * @return price Total required token amount for all SBTs
     */
    function queryPrice(uint256 tokenCount, address token) external returns (uint256 price);

    /**
     * @dev Purchase SBTs using server-signed authorization
     *
     * Enhanced purchase function that requires server-side signature verification.
     * Only transactions authorized by the server can be executed.
     *
     * Payment Process:
     * 1. User initiates payment with server-signed parameters:
     *    - Array of token IDs to mint from the configured SBT contract
     *    - Payment token address (ERC20.approve required for non-native OAS)
     *    - Payment amount in the specified token (includes slippage tolerance, calculated off-chain)
     *    - Minimum revenue OAS amount for protocol revenue recipient
     *    - Server signature for authorization
     *    - Excess payments are refunded using the same token type
     * 2. Verifies server signature against purchase order data
     * 3. For non-native OAS payments, receives tokens via ERC20.transferFrom
     *    - POAS payments are received as native OAS
     * 4. Calculates required SMP token amount for the purchase
     * 5. For non-SMP payments, swaps to required SMP amount using LP.
     *    Excess payment tokens are refunded at this stage.
     * 6. Burns SMP at pre-configured ratio
     * 7. Provides SMP to LP at pre-configured ratio (ensures BPT > 0)
     *    - LP tokens are sent to pre-configured dedicated address
     * 8. Swaps remaining SMP to OAS via LP and sends to pre-configured address
     *    - Validates that revenue OAS meets minimum threshold
     * 9. Mints and transfers SBTs to msg.sender
     * 10. Refunds excess payment tokens remaining from step 5 swap
     *
     * @param tokenIds Array of token IDs to mint from the configured SBT contract
     * @param paymentToken Token address for payment:
     *              - 0x0000000000000000000000000000000000000000 for native OAS
     *              - Dynamic addresses for POAS and SMP (must be registered)
     * @param amount Total payment amount in the specified token for all SBTs.
     *               This amount includes slippage tolerance and is calculated off-chain.
     *               Note: Obtain the base price using queryPrice and apply slippage tolerance.
     * @param minRevenueOAS Minimum OAS revenue that revenueRecipient should receive
     * @param purchaseId Globally unique purchase ID for replay protection
     * @param deadline Signature expiration timestamp
     * @param signature Server signature for the purchase order (buyer is always msg.sender)
     */
    function purchase(
        uint256[] calldata tokenIds,
        address paymentToken,
        uint256 amount,
        uint256 minRevenueOAS,
        uint256 purchaseId,
        uint256 deadline,
        bytes calldata signature
    ) external payable;

    /**
     * @dev Purchase SBTs without payment using server-signed authorization
     *
     * This method allows minting SBTs for free while still requiring a
     * server-issued signature for replay protection and access control.
     *
     * @param tokenIds Array of token IDs to mint from the configured SBT contract
     * @param purchaseId Globally unique purchase ID for replay protection
     * @param deadline Signature expiration timestamp
     * @param signature Server signature for the free purchase order (buyer is always msg.sender)
     */
    function freePurchase(
        uint256[] calldata tokenIds,
        uint256 purchaseId,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /**
     * @dev Mint SBTs directly as contract owner
     *
     * Administrative function allowing the contract owner to mint SBTs
     * without payment. Useful for airdrops, rewards, or special events.
     *
     * @param recipients Array of addresses to receive the minted SBTs
     * @param tokenIds Array of token IDs to mint from the configured SBT contract
     */
    function mintByOwner(address[] calldata recipients, uint256[] calldata tokenIds) external;

    /**
     * @dev Set the authorized server signer address
     *
     * Only the contract owner can update the signer address.
     * This address is used to verify purchase order signatures.
     *
     * @param newSigner New signer address (cannot be zero address)
     */
    function setSigner(address newSigner) external;

    /**
     * @dev Get the current authorized server signer address
     * @return signer Current signer address
     */
    function getSigner() external view returns (address signer);

    /**
     * @dev Check if a purchase ID has been used
     * @param purchaseId Purchase ID to check
     * @return used Whether the purchase ID has been used
     */
    function isUsedPurchaseId(uint256 purchaseId) external view returns (bool used);

    /**
     * @dev Set the SBT contract address
     *
     * Only the contract owner can update the SBT contract address.
     * This contract is used for minting SBTs in purchase and mintByOwner functions.
     *
     * @param newSBTContract New SBT contract address (cannot be zero address)
     */
    function setSBTContract(ISBTSaleERC721 newSBTContract) external;

    /**
     * @dev Get the current SBT contract address
     * @return sbtContract Current SBT contract address
     */
    function getSBTContract() external view returns (ISBTSaleERC721 sbtContract);

    // View functions

    /**
     * @dev Get current WOAS address
     * @return woas Current WOAS token address (used internally for Balancer V2 pool)
     */
    function getWOAS() external view returns (address woas);

    /**
     * @dev Get current POAS address
     * @return poas Current POAS token address
     */
    function getPOAS() external view returns (address poas);

    /**
     * @dev Get current SMP address
     * @return smp SMP token address
     */
    function getSMP() external view returns (address smp);

    /**
     * @dev Get current POASMinter contract address
     * @return poasMinter Current POASMinter contract address
     */
    function getPOASMinter() external view returns (address poasMinter);

    /**
     * @dev Get Balancer V2 pool address
     * @return pool Address of the Balancer V2 pool for WOAS-SMP
     */
    function getLiquidityPool() external view returns (address pool);

    /**
     * @dev Get LP token recipient address
     * @return recipient Address receiving LP tokens (BPT)
     */
    function getLPRecipient() external view returns (address recipient);

    /**
     * @dev Get revenue recipient address
     * @return recipient Address receiving OAS revenue
     */
    function getRevenueRecipient() external view returns (address recipient);

    /**
     * @dev Get SMP burn ratio
     * @return burnRatio SMP burn ratio in basis points
     */
    function getSMPBurnRatio() external view returns (uint256 burnRatio);

    /**
     * @dev Get SMP liquidity provision ratio
     * @return liquidityRatio SMP liquidity provision ratio in basis points
     */
    function getSMPLiquidityRatio() external view returns (uint256 liquidityRatio);
}
