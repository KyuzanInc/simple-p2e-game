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
    // Signature verification structure for EIP-712
    struct PurchaseOrder {
        uint256 purchaseId;  // Globally unique purchase ID
        address buyer;
        uint256[] tokenIds;
        address paymentToken;
        uint256 amount;
        uint256 maxSlippageBps; // Maximum slippage in basis points (1 BPS = 0.01%)
        uint256 deadline;
    }

    // Errors
    error InvalidPaymentToken(); // 0x56e7ec5f
    error InvalidRecipient(); // 0x9c8d2cd2
    error InvalidPaymentAmount(); // 0xfc512fde
    error InvalidProtocolValue(); // 0x3c88b7e9
    error InvalidPool(); // 0x2083cd40
    error InvalidAddress(); // 0xe6c4247b
    error InvalidSwap(string message); // 0x3bea1958
    error NoItems(); // 0x0483ac36
    error TooManyItems(); // 0x1f645e1a
    error ArrayLengthMismatch(); // 0xa24a13a6
    error TransferFailed(); // 0x90b8ec18
    error InvalidSignature(); // 0x8baa579f
    error ExpiredDeadline(); // 0x3a5c06d1  
    error PurchaseIdAlreadyUsed(); // 0x715018a6
    error InvalidSigner(); // 0xafb5b3b8
    error BuyerMismatch(); // 0x892b78e2
    error SlippageExceeded(); // Slippage tolerance exceeded

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
    event OwnerMinted(
        address indexed owner,
        address[] recipients,
        uint256[] tokenIds
    );

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
    function queryPrice(uint256 tokenCount, address token)
        external
        returns (uint256 price);

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
     *    - Payment amount in the specified token (not SMP amount)
     *    - Server signature for authorization
     *    - Excess payments are refunded using the same token type
     * 2. Verifies server signature against purchase order data
     * 3. For non-native OAS payments, receives tokens via ERC20.transferFrom
     *    - POAS payments are received as native OAS
     * 4. Calculates required SMP token amount for the purchase
     * 5. For non-SMP payments, swaps to required SMP amount using LP.
     *    Excess payment tokens are refunded at this stage.
     * 6. Burns SMP at pre-configured ratio
     * 7. Provides SMP to LP at pre-configured ratio
     *    - LP tokens are sent to pre-configured dedicated address
     * 8. Swaps remaining SMP to OAS via LP and sends to pre-configured address
     * 9. Mints and transfers SBTs to msg.sender
     * 10. Refunds excess payment tokens remaining from step 5 swap
     *
     * @param tokenIds Array of token IDs to mint from the configured SBT contract
     * @param buyer Address of the authorized buyer (must match msg.sender)
     * @param paymentToken Token address for payment:
     *              - 0x0000000000000000000000000000000000000000 for native OAS
     *              - Dynamic addresses for POAS and SMP (must be registered)
     * @param amount Total payment amount in the specified token for all SBTs.
     *               Note: Obtain this value beforehand using queryPrice.
     * @param purchaseId Globally unique purchase ID for replay protection
     * @param deadline Signature expiration timestamp
     * @param signature Server signature for the purchase order
     */
    function purchase(
        uint256[] calldata tokenIds,
        address buyer,
        address paymentToken,
        uint256 amount,
        uint256 maxSlippageBps,
        uint256 purchaseId,
        uint256 deadline,
        bytes calldata signature
    ) external payable;

    /**
     * @dev Mint SBTs directly as contract owner
     *
     * Administrative function allowing the contract owner to mint SBTs
     * without payment. Useful for airdrops, rewards, or special events.
     *
     * @param recipients Array of addresses to receive the minted SBTs
     * @param tokenIds Array of token IDs to mint from the configured SBT contract
     */
    function mintByOwner(
        address[] calldata recipients,
        uint256[] calldata tokenIds
    ) external;

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
