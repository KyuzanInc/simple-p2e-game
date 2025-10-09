// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

// OpenZeppelin
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable2StepUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// BalancerV2
import {IVault} from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import {IAsset} from "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import {IERC20 as BalancerV2IERC20} from
    "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import {WeightedPoolUserData} from
    "@balancer-labs/v2-interfaces/contracts/pool-weighted/WeightedPoolUserData.sol";

// Local interfaces
import {ISBTSale} from "./interfaces/ISBTSale.sol";
import {IVaultPool} from "./interfaces/IVaultPool.sol";
import {ISBTSaleERC721} from "./interfaces/ISBTSaleERC721.sol";
import {IPOAS} from "./interfaces/IPOAS.sol";
import {IPOASMinter} from "./interfaces/IPOASMinter.sol";

/**
 * @title SBTSale
 * @dev Contract for selling SBTs using multiple payment tokens. Handles SMP burning,
 *      liquidity provision and revenue distribution.
 */
contract SBTSale is
    ISBTSale,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable
{
    using SafeERC20 for IERC20;
    using SignatureChecker for address;

    /// @dev Data structure for swap operation
    struct SwapData {
        address tokenIn; // Token to swap from
        address tokenOut; // Token to swap to
        uint256 amountIn; // Amount to swap
        uint256 amountOut; // Minimum amount to receive (0 = protocol determined)
        address recipient; // Address to receive the swapped tokens
    }

    /// @dev Data structure to avoid stack too deep errors
    struct PurchaseData {
        uint256 requiredSMP;
        uint256 burnSMP;
        uint256 liquiditySMP;
        uint256 revenueSMP;
        uint256 revenueOAS;
        uint256 actualAmount;
        uint256 refundAmount;
    }

    // Native OAS and WOAS addresses
    address private constant NATIVE_OAS = address(0);

    // Basis points for ratio calculations (10000 = 100%)
    uint256 public constant MAX_BASIS_POINTS = 10_000;

    // Maximum batch size for array operations
    uint256 public constant MAX_BATCH_SIZE = 200;

    // EIP-712 constants
    bytes32 private constant PURCHASE_ORDER_TYPEHASH = keccak256(
        "PurchaseOrder(uint256 purchaseId,address buyer,uint256[] tokenIds,address paymentToken,uint256 amount,uint256 minRevenueOAS,uint256 deadline)"
    );
    bytes32 private constant FREE_PURCHASE_ORDER_TYPEHASH = keccak256(
        "FreePurchaseOrder(uint256 purchaseId,address buyer,uint256[] tokenIds,uint256 deadline)"
    );

    // Immutable configuration
    address private immutable _vault;
    address private immutable _woas;
    address private immutable _poasMinter;
    address private immutable _smp;
    address private immutable _liquidityPool;
    address private immutable _lpRecipient;
    address private immutable _revenueRecipient;
    uint256 private immutable _smpBasePrice;
    uint256 private immutable _smpBurnRatio;
    uint256 private immutable _smpLiquidityRatio;

    // Signature verification state
    address private _signer;
    mapping(uint256 => bool) public usedPurchaseIds;

    // SBT contract configuration
    ISBTSaleERC721 private _sbtContract;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address poasMinter,
        address liquidityPool,
        address lpRecipient,
        address revenueRecipient,
        uint256 smpBasePrice,
        uint256 smpBurnRatio,
        uint256 smpLiquidityRatio
    ) {
        if (_isZeroAddress(poasMinter)) {
            revert InvalidAddress(poasMinter);
        }
        if (_isZeroAddress(liquidityPool)) {
            revert InvalidAddress(liquidityPool);
        }
        if (_isZeroAddress(lpRecipient)) {
            revert InvalidRecipient(lpRecipient);
        }
        if (_isZeroAddress(revenueRecipient)) {
            revert InvalidRecipient(revenueRecipient);
        }
        if (smpBasePrice == 0) {
            revert InvalidPaymentAmount(smpBasePrice);
        }
        if (smpBurnRatio + smpLiquidityRatio > MAX_BASIS_POINTS) {
            revert InvalidProtocolValue("smpBurnRatio + smpLiquidityRatio exceeds MAX_BASIS_POINTS");
        }

        // Get vault and pool tokens from liquidityPool
        IVaultPool pool = IVaultPool(liquidityPool);
        IVault vault = pool.getVault();
        (BalancerV2IERC20[] memory poolTokens,,) = vault.getPoolTokens(pool.getPoolId());
        if (poolTokens.length != 2) {
            revert InvalidPool();
        }

        // Get WOAS from vault.WETH() and determine SMP
        address woas = address(vault.WETH());
        address smp;
        if (address(poolTokens[0]) == woas) {
            smp = address(poolTokens[1]);
        } else if (address(poolTokens[1]) == woas) {
            smp = address(poolTokens[0]);
        } else {
            revert InvalidPool();
        }

        _vault = address(vault);
        _woas = woas;
        _poasMinter = poasMinter;
        _smp = smp;
        _liquidityPool = liquidityPool;
        _lpRecipient = lpRecipient;
        _revenueRecipient = revenueRecipient;
        _smpBurnRatio = smpBurnRatio;
        _smpLiquidityRatio = smpLiquidityRatio;
        _smpBasePrice = smpBasePrice;

        _disableInitializers();
    }

    /**
     * @notice Initialize the SBTSale contract with two-step ownership transfer
     * @dev This function is called during proxy deployment to set up the upgradeable contract.
     *      Uses OpenZeppelin's initializer pattern for upgradeable contracts.
     *      Initializes Ownable2Step, Ownable, ReentrancyGuard, and EIP712 modules.
     * @param initialOwner Address to be set as the initial owner with full administrative privileges
     */
    function initialize(address initialOwner) public initializer {
        __Ownable2Step_init();
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __EIP712_init("SBTSale", "1");
    }

    /// @dev Disable renounceOwnership to prevent accidental loss of control
    /// @notice This function is disabled to prevent accidental ownership renouncement
    function renounceOwnership() public view override onlyOwner {
        revert OwnershipCannotBeRenounced();
    }

    /// @inheritdoc ISBTSale
    function getWOAS() external view returns (address woas) {
        return _woas;
    }

    /// @inheritdoc ISBTSale
    function getPOAS() external view returns (address poas) {
        return IPOASMinter(_poasMinter).poas();
    }

    /// @inheritdoc ISBTSale
    function getSMP() external view returns (address smp) {
        return _smp;
    }

    /// @inheritdoc ISBTSale
    function getPOASMinter() external view returns (address poasMinter) {
        return _poasMinter;
    }

    /// @inheritdoc ISBTSale
    function getLiquidityPool() external view returns (address pool) {
        return _liquidityPool;
    }

    /// @inheritdoc ISBTSale
    function getLPRecipient() external view returns (address recipient) {
        return _lpRecipient;
    }

    /// @inheritdoc ISBTSale
    function getRevenueRecipient() external view returns (address recipient) {
        return _revenueRecipient;
    }

    /// @inheritdoc ISBTSale
    function getSMPBurnRatio() external view returns (uint256 burnRatio) {
        return _smpBurnRatio;
    }

    /// @inheritdoc ISBTSale
    function getSMPLiquidityRatio() external view returns (uint256 liquidityRatio) {
        return _smpLiquidityRatio;
    }

    /// @inheritdoc ISBTSale
    function setSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) {
            revert InvalidSigner(newSigner);
        }
        // No-op if setting the same value to avoid unnecessary event emission and gas cost
        if (newSigner == _signer) {
            return;
        }
        address oldSigner = _signer;
        _signer = newSigner;
        emit SignerUpdated(oldSigner, newSigner);
    }

    /// @inheritdoc ISBTSale
    function getSigner() external view returns (address) {
        return _signer;
    }

    /// @inheritdoc ISBTSale
    function isUsedPurchaseId(uint256 purchaseId) external view returns (bool) {
        return usedPurchaseIds[purchaseId];
    }

    /// @inheritdoc ISBTSale
    function setSBTContract(ISBTSaleERC721 newSBTContract) external onlyOwner {
        if (address(newSBTContract) == address(0)) {
            revert InvalidAddress(address(newSBTContract));
        }

        // No-op if setting the same value to avoid unnecessary event emission and gas cost
        if (newSBTContract == _sbtContract) {
            return;
        }

        // Verify contract implements required interfaces using ERC-165
        try IERC165(address(newSBTContract)).supportsInterface(type(ISBTSaleERC721).interfaceId)
        returns (bool supportsISBTSaleERC721) {
            if (!supportsISBTSaleERC721) {
                revert InvalidAddress(address(newSBTContract));
            }
        } catch {
            revert InvalidAddress(address(newSBTContract));
        }

        ISBTSaleERC721 oldContract = _sbtContract;
        _sbtContract = newSBTContract;
        emit SBTContractUpdated(address(oldContract), address(newSBTContract));
    }

    /// @inheritdoc ISBTSale
    function getSBTContract() external view returns (ISBTSaleERC721) {
        return _sbtContract;
    }

    /// @inheritdoc ISBTSale
    function mintByOwner(address[] calldata recipients, uint256[] calldata tokenIds)
        external
        onlyOwner
    {
        if (recipients.length == 0) {
            revert NoItems();
        }
        if (recipients.length > MAX_BATCH_SIZE) {
            revert TooManyItems(recipients.length, MAX_BATCH_SIZE);
        }
        if (recipients.length != tokenIds.length) {
            revert ArrayLengthMismatch(recipients.length, tokenIds.length);
        }
        if (address(_sbtContract) == address(0)) {
            revert InvalidAddress(address(_sbtContract));
        }

        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_isZeroAddress(recipients[i])) {
                revert InvalidAddress(recipients[i]);
            }
            _sbtContract.safeMint(recipients[i], tokenIds[i]);
        }

        emit OwnerMinted(msg.sender, recipients, tokenIds);
    }

    /// @inheritdoc ISBTSale
    /// @dev Note: This method is not a 'view' function due to Balancer V2 design constraints.
    ///            Therefore, callers must explicitly use `eth_call` to call it.
    function queryPrice(uint256 tokenCount, address paymentToken) public returns (uint256 price) {
        /// Note: Do not check msg.sender's token balances in this method or related methods.
        /// This method must return the same price regardless of who the caller is.
        /// `IVault.queryBatchSwap` is also designed to not depend on msg.sender's WOAS/SMP balances.

        if (tokenCount == 0) {
            revert NoItems();
        }
        if (!_isValidPaymentToken(paymentToken)) {
            revert InvalidPaymentToken(paymentToken);
        }

        uint256 smpPrice = _getTotalSMPPrice(tokenCount);
        return _isSMP(paymentToken) ? smpPrice : _getRequiredOASFromLP(smpPrice);
    }

    /// @inheritdoc ISBTSale
    function purchase(
        uint256[] calldata tokenIds,
        address paymentToken,
        uint256 amount,
        uint256 minRevenueOAS,
        uint256 purchaseId,
        uint256 deadline,
        bytes calldata signature
    ) external payable nonReentrant {
        // Note: Do not call _getRequiredOASFromLP within this method.
        // More precisely, do not call `IVault.queryBatchSwap` within methods that perform actual token swaps.
        // This makes the contract vulnerable to sandwich attacks that exploit the mempool.
        // Reference: https://docs-v2.balancer.fi/reference/swaps/batch-swaps.html#querybatchswap

        // Basic input validation
        if (tokenIds.length == 0) {
            revert NoItems();
        }
        if (tokenIds.length > MAX_BATCH_SIZE) {
            revert TooManyItems(tokenIds.length, MAX_BATCH_SIZE);
        }
        if (!_isValidPaymentToken(paymentToken)) {
            revert InvalidPaymentToken(paymentToken);
        }
        if (address(_sbtContract) == address(0)) {
            revert InvalidAddress(address(_sbtContract));
        }

        // Create purchase order for signature verification
        PurchaseOrder memory order = PurchaseOrder({
            purchaseId: purchaseId,
            buyer: msg.sender,
            tokenIds: tokenIds,
            paymentToken: paymentToken,
            amount: amount,
            minRevenueOAS: minRevenueOAS,
            deadline: deadline
        });

        // Signature verification
        if (usedPurchaseIds[purchaseId]) {
            revert PurchaseIdAlreadyUsed(purchaseId);
        }
        if (block.timestamp > deadline) {
            revert ExpiredDeadline(deadline, block.timestamp);
        }
        if (!_verifyPurchaseOrder(order, signature)) {
            revert InvalidSignature();
        }

        // Mark purchase ID as used
        usedPurchaseIds[purchaseId] = true;

        // Receive payment token from buyer
        _receiveToken(msg.sender, paymentToken, amount);

        // Initialize purchase data structure to avoid stack too deep
        PurchaseData memory data;

        // Calculate total SMP price required for all NFTs
        data.requiredSMP = _getTotalSMPPrice(tokenIds.length);

        // Swap payment token to SMP
        data.actualAmount = _payWithSwapToSMP(paymentToken, amount, data.requiredSMP);
        data.refundAmount = amount - data.actualAmount;

        // Burn configured percentage of SMP
        data.burnSMP = _burnSMP(data.requiredSMP);

        // Provide configured percentage of SMP to liquidity pool
        data.liquiditySMP = _provideLiquidity(data.requiredSMP);

        // Swap remaining SMP to OAS for protocol revenue
        data.revenueSMP = data.requiredSMP - data.burnSMP - data.liquiditySMP;
        if (data.revenueSMP > 0) {
            data.revenueOAS = _swapSMPtoOASForRevenueRecipient(data.revenueSMP, minRevenueOAS);
        }

        // Mint NFTs to buyer
        _mintNFTs(msg.sender, tokenIds);

        // Refund excess native OAS/POAS
        if (data.refundAmount > 0) {
            _refundAnyOAS(msg.sender, paymentToken, data.refundAmount);
        }

        // Emit comprehensive purchase event
        emit Purchased(
            msg.sender,
            tokenIds,
            paymentToken,
            data.actualAmount,
            data.refundAmount,
            data.burnSMP,
            data.liquiditySMP,
            data.revenueSMP,
            data.revenueOAS,
            _revenueRecipient,
            _lpRecipient,
            purchaseId
        );
    }

    /// @inheritdoc ISBTSale
    function freePurchase(
        uint256[] calldata tokenIds,
        uint256 purchaseId,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        if (tokenIds.length == 0) {
            revert NoItems();
        }
        if (tokenIds.length > MAX_BATCH_SIZE) {
            revert TooManyItems(tokenIds.length, MAX_BATCH_SIZE);
        }
        if (address(_sbtContract) == address(0)) {
            revert InvalidAddress(address(_sbtContract));
        }
        if (usedPurchaseIds[purchaseId]) {
            revert PurchaseIdAlreadyUsed(purchaseId);
        }
        if (block.timestamp > deadline) {
            revert ExpiredDeadline(deadline, block.timestamp);
        }

        FreePurchaseOrder memory order = FreePurchaseOrder({
            purchaseId: purchaseId,
            buyer: msg.sender,
            tokenIds: tokenIds,
            deadline: deadline
        });

        if (!_verifyFreePurchaseOrder(order, signature)) {
            revert InvalidSignature();
        }

        usedPurchaseIds[purchaseId] = true;

        _mintNFTs(msg.sender, tokenIds);

        emit Purchased(
            msg.sender,
            tokenIds,
            NATIVE_OAS,
            0,
            0,
            0,
            0,
            0,
            0,
            _revenueRecipient,
            _lpRecipient,
            purchaseId
        );
    }

    /// @dev Check if the address is zero
    function _isZeroAddress(address addr) internal pure returns (bool) {
        return addr == address(0);
    }

    /// @dev Hash a PurchaseOrder struct for EIP-712 signature verification
    function _hashPurchaseOrder(PurchaseOrder memory order) internal view returns (bytes32) {
        // Convert dynamic array to fixed-size hash for EIP-712
        // Use abi.encode instead of abi.encodePacked to prevent hash collisions
        bytes32 tokenIdsHash = keccak256(abi.encode(order.tokenIds));

        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    PURCHASE_ORDER_TYPEHASH,
                    order.purchaseId,
                    order.buyer,
                    tokenIdsHash,
                    order.paymentToken,
                    order.amount,
                    order.minRevenueOAS,
                    order.deadline
                )
            )
        );
    }

    function _hashFreePurchaseOrder(FreePurchaseOrder memory order)
        internal
        view
        returns (bytes32)
    {
        bytes32 tokenIdsHash = keccak256(abi.encode(order.tokenIds));

        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    FREE_PURCHASE_ORDER_TYPEHASH,
                    order.purchaseId,
                    order.buyer,
                    tokenIdsHash,
                    order.deadline
                )
            )
        );
    }

    /// @dev Verify purchase order signature
    function _verifyPurchaseOrder(PurchaseOrder memory order, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        if (_signer == address(0)) {
            return false;
        }

        bytes32 digest = _hashPurchaseOrder(order);
        return _signer.isValidSignatureNow(digest, signature);
    }

    function _verifyFreePurchaseOrder(FreePurchaseOrder memory order, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        if (_signer == address(0)) {
            return false;
        }

        bytes32 digest = _hashFreePurchaseOrder(order);
        return _signer.isValidSignatureNow(digest, signature);
    }

    /// @dev Check if the token is native OAS
    function _isNativeOAS(address paymentToken) internal pure returns (bool) {
        return paymentToken == NATIVE_OAS;
    }

    /// @dev Check if the token is POAS
    function _isPOAS(address paymentToken) internal view returns (bool) {
        return paymentToken == IPOASMinter(_poasMinter).poas();
    }

    /// @dev Check if the token is SMP
    function _isSMP(address paymentToken) internal view returns (bool) {
        return paymentToken == _smp;
    }

    /// @dev Validate if the payment token is supported
    function _isValidPaymentToken(address paymentToken) internal view returns (bool) {
        return _isNativeOAS(paymentToken) || _isPOAS(paymentToken) || _isSMP(paymentToken);
    }

    /// @dev Get pool assets array for WOAS-SMP pool
    /// @return assets Assets array with WOAS and SMP addresses following Balancer V2 address-sorted order
    /// @return woasPoolIndex Index of WOAS position in pool (determined by address ordering)
    /// @return smpPoolIndex Index of SMP position in pool (determined by address ordering)
    function _getPoolAssets()
        internal
        view
        returns (IAsset[] memory assets, uint8 woasPoolIndex, uint8 smpPoolIndex)
    {
        assets = new IAsset[](2);
        // Pool structure follows Balancer V2 address ordering requirement
        woasPoolIndex = _woas < _smp ? 0 : 1;
        smpPoolIndex = woasPoolIndex ^ 1; // 0->1, 1->0

        // Always return WOAS and SMP addresses
        // Caller will replace with ETH sentinel (address(0)) if needed for OAS/POAS operations
        assets[woasPoolIndex] = IAsset(_woas);
        assets[smpPoolIndex] = IAsset(_smp);
    }

    /// @dev Get the balance of a token in this contract
    /// @param paymentToken Token address
    /// @return Token balance held by this contract
    function _getBalance(address paymentToken) internal view returns (uint256) {
        // Native OAS and POAS use contract's OAS balance
        if (_isNativeOAS(paymentToken) || _isPOAS(paymentToken)) {
            return address(this).balance;
        } else {
            // ERC20 tokens use standard balanceOf
            return IERC20(paymentToken).balanceOf(address(this));
        }
    }

    /// @dev Get the total SMP price for a number of NFTs
    /// @param tokenCount Number of NFTs to calculate price for
    /// @return totalSMPPrice Total SMP required (tokenCount × base price)
    function _getTotalSMPPrice(uint256 tokenCount) internal view returns (uint256 totalSMPPrice) {
        if (tokenCount == 0) {
            revert NoItems();
        }
        // Note: _smpBasePrice is guaranteed to be non-zero (validated in constructor)

        // Calculate total: each NFT costs the base SMP price
        totalSMPPrice = tokenCount * _smpBasePrice;
    }

    /// @dev Receive token from buyer and validate amount
    /// @param from Address of the buyer
    /// @param paymentToken Payment token address
    /// @param amount Expected amount to receive
    function _receiveToken(address from, address paymentToken, uint256 amount) internal {
        // Native OAS: validate msg.value
        if (_isNativeOAS(paymentToken)) {
            if (msg.value != amount) {
                revert InvalidPaymentAmount(msg.value);
            }
            return;
        }

        // ERC20 tokens: msg.value must be zero
        if (msg.value != 0) {
            revert InvalidPaymentAmount(msg.value);
        }

        // Execute ERC20 transfer and validate received amount
        // Note: POAS burns tokens and sends equivalent OAS to this contract
        uint256 beforeBalance = _getBalance(paymentToken);
        IERC20(paymentToken).transferFrom(from, address(this), amount);
        uint256 receivedAmount = _getBalance(paymentToken) - beforeBalance;
        if (receivedAmount != amount) {
            revert InvalidPaymentAmount(receivedAmount);
        }
    }

    /// @dev Execute token swap via WOAS-SMP pool
    /// @param swapData Swap configuration data
    /// @return actualIn Actual input token amount swapped
    /// @return actualOut Actual output token amount swapped
    function _swap(SwapData memory swapData)
        internal
        returns (uint256 actualIn, uint256 actualOut)
    {
        if (swapData.amountIn == 0) {
            revert InvalidPaymentAmount(swapData.amountIn);
        }

        (IAsset[] memory assets, uint8 woasPoolIndex, uint8 smpPoolIndex) = _getPoolAssets();

        // Replace WOAS with ETH sentinel for native OAS/POAS operations
        // Balancer V2 automatically handles OAS <-> WOAS conversion when msg.value is provided
        // Check both tokenIn and tokenOut - one of them must be OAS/POAS when swapping with SMP
        if (
            _isNativeOAS(swapData.tokenIn) || _isPOAS(swapData.tokenIn)
                || _isNativeOAS(swapData.tokenOut) || _isPOAS(swapData.tokenOut)
        ) {
            assets[woasPoolIndex] = IAsset(address(0)); // ETH sentinel for OAS/POAS
        }

        // Map tokens to pool asset indices
        uint8 tokenInIndex = _isSMP(swapData.tokenIn) ? smpPoolIndex : woasPoolIndex;
        uint8 tokenOutIndex = tokenInIndex ^ 1; // Flip index: 0->1, 1->0

        // Configure swap parameters
        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(swapData.recipient),
            toInternalBalance: false
        });

        // Configure swap parameters based on whether exact output is required
        IVault.SwapKind swapKind;
        IVault.BatchSwapStep[] memory swaps;
        int256[] memory limits = new int256[](2);

        // Set maximum input limit for both swap types
        limits[tokenInIndex] = int256(swapData.amountIn);

        if (swapData.amountOut > 0) {
            // GIVEN_OUT: Specify exact output amount (e.g., exactly 150 SMP)
            // Used when we need precise output amount for protocol calculations
            swapKind = IVault.SwapKind.GIVEN_OUT;
            swaps = _createSwapSteps(swapData.amountOut, tokenInIndex, tokenOutIndex);
            limits[tokenOutIndex] = -int256(swapData.amountOut); // Negative = exact output required
        } else {
            // GIVEN_IN: Specify exact input amount (e.g., swap all available SMP)
            // Used when we want to swap all of a token without caring about exact output
            swapKind = IVault.SwapKind.GIVEN_IN;
            swaps = _createSwapSteps(swapData.amountIn, tokenInIndex, tokenOutIndex);
            limits[tokenOutIndex] = int256(0); // Zero = no minimum output constraint
        }

        // Deadline set to max value since purchase() already validates deadline via signature
        // Transaction execution is atomic, so additional deadline check is redundant
        uint256 deadline = type(uint256).max;

        int256[] memory deltas;
        if (_isNativeOAS(swapData.tokenIn) || _isPOAS(swapData.tokenIn)) {
            // Native OAS swap: Vault automatically wraps to WOAS internally
            deltas = IVault(_vault).batchSwap{value: swapData.amountIn}({
                kind: swapKind,
                swaps: swaps,
                assets: assets,
                funds: funds,
                limits: limits,
                deadline: deadline
            });
        } else {
            // ERC20 token swap (SMP)
            deltas = IVault(_vault).batchSwap({
                kind: swapKind,
                swaps: swaps,
                assets: assets,
                funds: funds,
                limits: limits,
                deadline: deadline
            });
        }

        if (deltas[tokenInIndex] < 0 || deltas[tokenOutIndex] > 0) {
            revert InvalidSwap("Unexpected balance changes");
        }
        actualIn = uint256(deltas[tokenInIndex]);
        actualOut = uint256(-deltas[tokenOutIndex]);

        if (actualIn > swapData.amountIn) {
            revert InvalidSwap("Input token exceeded limit");
        }
        // Validates exact output amount when GIVEN_OUT mode is used (amountOut > 0)
        // This check makes redundant checks in callers like _payWithSwapToSMP() unnecessary
        if (swapData.amountOut > 0 && actualOut != swapData.amountOut) {
            revert InvalidSwap("Output token below required amount");
        }
    }

    /// @dev Swap payment tokens to SMP via WOAS-SMP liquidity pool
    /// @param paymentToken Token to swap from (NATIVE_OAS/POAS/SMP)
    /// @param paymentAmount Payment token amount used for swap input
    /// @param requiredSMP SMP token amount required for swap output
    /// @return actualIn Actual input token amount used in swap
    function _payWithSwapToSMP(address paymentToken, uint256 paymentAmount, uint256 requiredSMP)
        internal
        returns (uint256 actualIn)
    {
        if (_isSMP(paymentToken)) {
            // Already SMP, no swap needed - use exact required amount
            // Note: Excess SMP (paymentAmount - requiredSMP) will be refunded
            actualIn = requiredSMP;
        } else {
            // Execute swap: Native OAS -> SMP (Vault handles OAS->WOAS conversion)
            // Note: _swap() validates that actualOut equals requiredSMP
            (actualIn,) = _swap(
                SwapData({
                    tokenIn: paymentToken, // Native OAS (including converted POAS) is passed as address(0)
                    tokenOut: _smp,
                    amountIn: paymentAmount,
                    amountOut: requiredSMP, // Expect exactly this amount (GIVEN_OUT)
                    recipient: address(this)
                })
            );
        }
    }

    /// @dev Create BatchSwapStep for token swap
    /// @param amount Amount to swap
    /// @param tokenInIndex Index of input token in assets array
    /// @param tokenOutIndex Index of output token in assets array
    /// @return swaps BatchSwapStep array
    function _createSwapSteps(uint256 amount, uint8 tokenInIndex, uint8 tokenOutIndex)
        internal
        view
        returns (IVault.BatchSwapStep[] memory swaps)
    {
        swaps = new IVault.BatchSwapStep[](1);
        swaps[0] = IVault.BatchSwapStep({
            poolId: IVaultPool(_liquidityPool).getPoolId(),
            assetInIndex: tokenInIndex,
            assetOutIndex: tokenOutIndex,
            amount: amount,
            userData: ""
        });
    }

    /// @dev Get required OAS amount from LP to obtain specific SMP amount
    ///      Note: that this function is not 'view' (due to implementation details)
    /// @param requiredSMP Required SMP amount to obtain
    /// @return requiredOAS Required OAS amount to swap via LP (Vault handles WOAS conversion)
    function _getRequiredOASFromLP(uint256 requiredSMP) internal returns (uint256 requiredOAS) {
        (IAsset[] memory assets, uint8 woasPoolIndex, uint8 smpPoolIndex) = _getPoolAssets();

        // Replace WOAS with ETH sentinel for clarity since this function is called
        // when user wants to pay with OAS/POAS (not WOAS)
        // Note: queryBatchSwap works with both WOAS address and ETH sentinel (address(0))
        // since it's a simulation that doesn't involve actual token transfers,
        // but we use ETH sentinel to make the intent clearer
        assets[woasPoolIndex] = IAsset(address(0));

        // Create swap steps for GIVEN_OUT query
        IVault.BatchSwapStep[] memory swaps =
            _createSwapSteps(requiredSMP, woasPoolIndex, smpPoolIndex);
        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        // Query batch swap to get required input amount
        int256[] memory deltas = IVault(_vault).queryBatchSwap({
            kind: IVault.SwapKind.GIVEN_OUT,
            swaps: swaps,
            assets: assets,
            funds: funds
        });

        // Get required OAS amount (will be positive)
        requiredOAS = uint256(deltas[woasPoolIndex]);
    }

    /// @dev Burn SMP tokens according to configured burn ratio
    /// @param totalSMP Total SMP amount to be processed
    /// @return burnedSMP Actual amount of SMP burned
    function _burnSMP(uint256 totalSMP) internal returns (uint256 burnedSMP) {
        burnedSMP = (totalSMP * _smpBurnRatio) / MAX_BASIS_POINTS;
        ERC20Burnable(_smp).burn(burnedSMP);
    }

    /// @dev Provide configured ratio of SMP to LP as single-sided liquidity
    /// @param totalSMP Total SMP amount to be processed
    /// @return providedSMP Actual amount of SMP provided to LP
    function _provideLiquidity(uint256 totalSMP) internal returns (uint256 providedSMP) {
        // Calculate liquidity provision amount based on configured ratio
        providedSMP = (totalSMP * _smpLiquidityRatio) / MAX_BASIS_POINTS;

        // Setup pool interaction parameters
        (IAsset[] memory assets, uint8 woasPoolIndex, uint8 smpPoolIndex) = _getPoolAssets();
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[woasPoolIndex] = 0; // No WOAS (single-sided liquidity)
        maxAmountsIn[smpPoolIndex] = providedSMP; // Only SMP

        // Execute pool join with single-sided SMP liquidity
        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(
                WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, maxAmountsIn, 0
            ),
            fromInternalBalance: false
        });

        // Approve vault to spend SMP
        IVault vault = IVault(_vault);
        IERC20(_smp).approve(address(vault), providedSMP);

        // Get LP recipient's BPT balance before liquidity provision
        // Note: Pool contract itself is the BPT (ERC20) token in Balancer V2
        IVaultPool pool = IVaultPool(_liquidityPool);
        uint256 bptBefore = pool.balanceOf(_lpRecipient);

        // Provide liquidity to the pool
        vault.joinPool({
            poolId: pool.getPoolId(),
            sender: address(this),
            recipient: _lpRecipient, // LP tokens sent directly to LP recipient
            request: request
        });

        // Validate that BPT was received
        uint256 bptReceived = pool.balanceOf(_lpRecipient) - bptBefore;
        if (bptReceived == 0) {
            revert InsufficientBPTReceived(bptReceived);
        }
    }

    /// @dev Swap SMP to OAS and send to revenue recipient
    /// @param revenueSMP Amount of SMP to swap for revenue
    /// @param minRevenueOAS Minimum OAS revenue that revenueRecipient should receive
    /// @return revenueOAS Amount of OAS received from swap
    function _swapSMPtoOASForRevenueRecipient(uint256 revenueSMP, uint256 minRevenueOAS)
        internal
        returns (uint256 revenueOAS)
    {
        IERC20(_smp).approve(_vault, revenueSMP);

        // Execute swap: SMP -> native OAS
        (, revenueOAS) = _swap(
            SwapData({
                tokenIn: _smp,
                tokenOut: NATIVE_OAS,
                amountIn: revenueSMP,
                amountOut: 0, // Accept any amount out (GIVEN_IN)
                recipient: _revenueRecipient // OAS sent directly to revenue recipient
            })
        );

        // Validate revenue meets minimum threshold
        if (revenueOAS < minRevenueOAS) {
            revert InsufficientRevenue(minRevenueOAS, revenueOAS);
        }
    }

    /// @dev Mint SBTs to buyer from the configured SBT contract
    /// @param to Address to receive the minted SBTs
    /// @param tokenIds Array of token IDs to mint
    function _mintNFTs(address to, uint256[] calldata tokenIds) internal {
        if (address(_sbtContract) == address(0)) {
            revert InvalidAddress(address(_sbtContract));
        }

        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ++i) {
            _sbtContract.safeMint(to, tokenIds[i]);
        }
    }

    /// @dev Refund excess payment tokens (native OAS/POAS) using the same token type
    function _refundAnyOAS(address to, address paymentToken, uint256 amount) internal {
        if (_isNativeOAS(paymentToken)) {
            Address.sendValue(payable(to), amount);
        } else if (_isPOAS(paymentToken)) {
            IPOASMinter(_poasMinter).mint{value: amount}(to, amount);
        }
    }

    receive() external payable {}
}
