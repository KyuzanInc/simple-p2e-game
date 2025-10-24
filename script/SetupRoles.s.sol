// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {SoulboundToken} from "../src/SoulboundToken.sol";
import {SBTSale} from "../src/SBTSale.sol";
import {ISBTSaleERC721} from "../src/interfaces/ISBTSaleERC721.sol";

/**
 * @title SetupRoles
 * @notice Sets up all necessary roles and configurations after deployment
 * @dev This script should be run after deploying both SoulboundToken and SBTSale contracts
 */
contract SetupRoles is Script {
    function run() external {
        // Load configuration from environment variables
        address sbtProxy = vm.envAddress("SBT_PROXY");
        address sbtSaleProxy = vm.envAddress("SBTSALE_PROXY");
        address signerAddress = vm.envAddress("SIGNER_ADDRESS");

        console.log("=== Setup Configuration ===");
        console.log("SBT Proxy:", sbtProxy);
        console.log("SBTSale Proxy:", sbtSaleProxy);
        console.log("Signer Address:", signerAddress);

        // Support both PRIVATE_KEY (standard) and DEPLOYER_ADDRESS (Fireblocks)
        // When using Fireblocks with --unlocked flag, use DEPLOYER_ADDRESS
        // Otherwise, use PRIVATE_KEY for standard deployment
        address deployer = vm.envOr("DEPLOYER_ADDRESS", address(0));

        if (deployer != address(0)) {
            // Fireblocks deployment: use address directly
            console.log("Deployer (Fireblocks):", deployer);
            console.log("");
            vm.startBroadcast(deployer);
        } else {
            // Standard deployment: use private key
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
            deployer = vm.addr(deployerPrivateKey);
            console.log("Deployer (Private Key):", deployer);
            console.log("");
            vm.startBroadcast(deployerPrivateKey);
        }

        SoulboundToken sbt = SoulboundToken(sbtProxy);
        SBTSale sbtSale = SBTSale(payable(sbtSaleProxy));

        // Step 1: Set signer in SBTSale
        console.log("=== Step 1: Setting Signer ===");
        address currentSigner = sbtSale.getSigner();
        console.log("Current signer:", currentSigner);

        if (currentSigner != signerAddress) {
            sbtSale.setSigner(signerAddress);
            console.log("Signer set to:", signerAddress);
        } else {
            console.log("Signer already set correctly");
        }
        console.log("");

        // Step 2: Set SBT contract in SBTSale
        console.log("=== Step 2: Setting SBT Contract ===");
        address currentSBTContract = address(sbtSale.getSBTContract());
        console.log("Current SBT contract:", currentSBTContract);

        if (currentSBTContract != sbtProxy) {
            sbtSale.setSBTContract(ISBTSaleERC721(sbtProxy));
            console.log("SBT contract set to:", sbtProxy);
        } else {
            console.log("SBT contract already set correctly");
        }
        console.log("");

        // Step 3: Grant MINTER_ROLE to SBTSale
        console.log("=== Step 3: Granting MINTER_ROLE ===");
        bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
        console.log("MINTER_ROLE:", vm.toString(MINTER_ROLE));

        bool hasMinterRole = sbt.hasRole(MINTER_ROLE, sbtSaleProxy);
        console.log("SBTSale has MINTER_ROLE:", hasMinterRole);

        if (!hasMinterRole) {
            sbt.grantRole(MINTER_ROLE, sbtSaleProxy);
            console.log("MINTER_ROLE granted to:", sbtSaleProxy);
        } else {
            console.log("MINTER_ROLE already granted");
        }
        console.log("");

        vm.stopBroadcast();

        // Final verification
        console.log("=== Final Verification ===");
        console.log("Signer:", sbtSale.getSigner());
        console.log("SBT Contract:", address(sbtSale.getSBTContract()));
        console.log("MINTER_ROLE granted:", sbt.hasRole(MINTER_ROLE, sbtSaleProxy));
        console.log("");
        console.log("=== Setup Complete ===");
    }
}
