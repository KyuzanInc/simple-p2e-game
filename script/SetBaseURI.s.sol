// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {SoulboundToken} from "../src/SoulboundToken.sol";

/**
 * @title SetBaseURI
 * @notice Updates the base URI for the SoulboundToken contract
 * @dev This script should be run by an account with DEFAULT_ADMIN_ROLE
 */
contract SetBaseURI is Script {
    function run() external {
        // Load configuration from environment variables
        address sbtProxy = vm.envAddress("SBT_PROXY");
        string memory newBaseURI = vm.envString("SBT_BASE_URI");

        console.log("=== SetBaseURI Configuration ===");
        console.log("SBT Proxy:", sbtProxy);
        console.log("New Base URI:", newBaseURI);

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

        // Check current base URI by attempting to get tokenURI for a hypothetical token
        console.log("=== Updating Base URI ===");

        // Verify deployer has DEFAULT_ADMIN_ROLE
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;
        bool hasAdminRole = sbt.hasRole(DEFAULT_ADMIN_ROLE, deployer);
        console.log("Deployer has DEFAULT_ADMIN_ROLE:", hasAdminRole);

        if (!hasAdminRole) {
            console.log("ERROR: Deployer does not have DEFAULT_ADMIN_ROLE");
            console.log("Cannot update base URI without admin role");
            vm.stopBroadcast();
            revert("Missing DEFAULT_ADMIN_ROLE");
        }

        // Set new base URI
        sbt.setBaseURI(newBaseURI);
        console.log("Base URI updated to:", newBaseURI);
        console.log("");

        vm.stopBroadcast();

        console.log("=== Update Complete ===");
    }
}
