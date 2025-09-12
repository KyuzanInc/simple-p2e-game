// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SBTSale.sol";
import "../src/interfaces/ISBTSaleERC721.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract PurchaseWithSMP is Script {
    // Updated EIP-712 type definitions to match the contract
    bytes32 private constant PURCHASE_ORDER_TYPEHASH = keccak256(
        "PurchaseOrder(uint256 purchaseId,address buyer,uint256[] tokenIds,address paymentToken,uint256 amount,uint256 maxSlippageBps,uint256 deadline)"
    );

    // Storage struct to avoid stack too deep
    struct PurchaseParams {
        address sbtSaleAddress;
        address nftAddress;
        address paymentToken;
        uint256 purchaseAmount;
        address user;
        address signer;
        uint256 deadline;
        uint256[] tokenIds;
        uint16[] typeIds;
        uint256 purchaseId;
        uint256 maxSlippageBps;
    }

    struct PurchaseItem {
        ISBTSaleERC721 nftContract;
        uint256[] tokenIds;
        uint16[] typeIds;
    }

    function run() external {
        // Contract addresses
        PurchaseParams memory params;
        params.sbtSaleAddress = vm.envAddress("SBT_SALE_ADDRESS");
        params.nftAddress = vm.envAddress("NFT_CONTRACT_ADDRESS");
        params.paymentToken = vm.envAddress("SMP_TOKEN_ADDRESS"); // SMP token
        params.purchaseAmount = 1;

        // Set NFT data based on purchase amount
        params.tokenIds = new uint256[](params.purchaseAmount);
        params.typeIds = new uint16[](params.purchaseAmount);

        for (uint256 i = 0; i < params.purchaseAmount; i++) {
            params.tokenIds[i] = 12_345 + i; // Generate sequential tokenIds starting from 12345
            params.typeIds[i] = uint16(i + 1); // Rotate through type IDs 1-90
        }

        // Get deployer/user key
        uint256 userPrivateKey = vm.envUint("PRIVATE_KEY");
        params.user = vm.addr(userPrivateKey);
        params.signer = vm.addr(userPrivateKey);

        vm.startBroadcast(userPrivateKey);

        SBTSale sbtSale = SBTSale(payable(params.sbtSaleAddress));

        console.log("=== Setup Phase ===");
        console.log("User address:", params.user);
        console.log("Signer address:", params.signer);
        console.log("SBTSale owner:", sbtSale.owner());
        console.log("Number of tokens:", params.tokenIds.length);

        // Setup if user is owner
        setupContractIfOwner(sbtSale, params);

        // Set authorized signer
        sbtSale.setSigner(params.signer);
        console.log("Set authorized signer:", params.signer);

        // Check balances and approve
        checkAndApprove(sbtSale, params);

        // Set deadline and other signature params
        params.deadline = block.timestamp + 1_000_000; // 5 minutes from now
        params.purchaseId = uint256(
            keccak256(abi.encodePacked(block.timestamp, params.user, params.tokenIds.length))
        );
        params.maxSlippageBps = 500; // 5% max slippage

        // No need to encode purchase data - contract takes tokenIds directly

        // Stop broadcast to sign off-chain
        vm.stopBroadcast();

        // Calculate actual price for signature
        uint256 actualPrice = sbtSale.queryPrice(params.tokenIds.length, params.paymentToken);
        params.purchaseAmount = actualPrice; // Update to actual price for signature

        // Generate signature with correct parameters
        bytes memory signature = generateSignature(params, userPrivateKey);

        // Resume broadcast for the actual purchase
        vm.startBroadcast(userPrivateKey);

        console.log("=== Purchase Phase ===");
        console.log("Attempting purchase with signature...");
        console.logBytes(signature);

        //executePurchase(sbtSale, params.tokenIds, params.user, params.paymentToken, actualPrice, params.maxSlippageBps, params.purchaseId, params.deadline, signature);

        vm.stopBroadcast();
    }

    function setupContractIfOwner(SBTSale sbtSale, PurchaseParams memory params) internal {
        ISBTSaleERC721 nft = ISBTSaleERC721(params.nftAddress);
        sbtSale.setSBTContract(nft);
        console.log("Added NFT as supported soulbound token");

        // Grant MINTER role to SBTSale contract
        bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
        IAccessControl(params.nftAddress).grantRole(MINTER_ROLE, address(sbtSale));
        console.log("Granted MINTER role to SBTSale contract");
    }

    function checkAndApprove(SBTSale sbtSale, PurchaseParams memory params) internal {
        // Check user's SMP balance
        IERC20 smp = IERC20(params.paymentToken);
        uint256 userBalance = smp.balanceOf(params.user);
        console.log("User SMP balance:", userBalance);

        // Query price
        uint256 price = sbtSale.queryPrice(params.tokenIds.length, params.paymentToken);
        console.log("Price for", params.tokenIds.length, "NFT(s):", price);

        require(userBalance >= price, "Insufficient SMP balance");

        // Approve SMP spending
        smp.approve(params.sbtSaleAddress, price);
        console.log("Approved SMP spending");
    }

    function executePurchase(
        SBTSale sbtSale,
        uint256[] memory tokenIds,
        address buyer,
        address paymentToken,
        uint256 amount,
        uint256 maxSlippageBps,
        uint256 purchaseId,
        uint256 deadline,
        bytes memory signature
    ) internal {
        IERC20 smp = IERC20(paymentToken);

        try sbtSale.purchase(
            tokenIds, buyer, paymentToken, amount, maxSlippageBps, purchaseId, deadline, signature
        ) {
            console.log("Purchase successful!");
            console.log("NFTs minted:", tokenIds.length);
            for (uint256 i = 0; i < tokenIds.length; i++) {
                console.log("- Token ID:", tokenIds[i]);
            }
            console.log("New SMP balance:", smp.balanceOf(msg.sender));
        } catch Error(string memory reason) {
            console.log("Purchase failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Purchase failed with low-level error");
            console.logBytes(lowLevelData);
        }
    }

    function generateSignature(PurchaseParams memory params, uint256 signerPrivateKey)
        internal
        view
        returns (bytes memory)
    {
        // Hash tokenIds array to match contract's implementation
        bytes32 tokenIdsHash = keccak256(abi.encode(params.tokenIds));

        // Create purchase struct hash matching contract's _hashPurchaseOrder
        bytes32 structHash = keccak256(
            abi.encode(
                PURCHASE_ORDER_TYPEHASH,
                params.purchaseId,
                params.user,
                tokenIdsHash,
                params.paymentToken,
                params.purchaseAmount,
                params.maxSlippageBps,
                params.deadline
            )
        );

        // Manually construct domain separator to match contract's EIP712
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("SBTSale")),
                keccak256(bytes("1")),
                block.chainid,
                params.sbtSaleAddress
            )
        );

        // Create EIP-712 message hash
        bytes32 messageHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        console.log("Domain separator:", vm.toString(domainSeparator));
        console.log("Struct hash:", vm.toString(structHash));
        console.log("Message hash to sign:", vm.toString(messageHash));

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);

        // Combine into signature
        return abi.encodePacked(r, s, v);
    }
}
