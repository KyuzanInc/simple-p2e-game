// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title UpgradeSBTSale
 * @notice Upgrades the SBTSale proxy to a new implementation.
 */
contract UpgradeSBTSale is Script {
    function run() external {
        // Support both PRIVATE_KEY (standard) and DEPLOYER_ADDRESS (Fireblocks)
        // When using Fireblocks with --unlocked flag, use DEPLOYER_ADDRESS
        // Otherwise, use PRIVATE_KEY for standard deployment
        address deployer = vm.envOr("DEPLOYER_ADDRESS", address(0));

        if (deployer != address(0)) {
            // Fireblocks deployment: use address directly
            vm.startBroadcast(deployer);
        } else {
            // Standard deployment: use private key
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
            vm.startBroadcast(deployerPrivateKey);
        }

        address proxyAdminAddress = vm.envAddress("SBTSALE_PROXY_ADMIN");
        address proxyAddress = vm.envAddress("SBTSALE_PROXY");
        address newImplementation = vm.envAddress("SBTSALE_IMPLEMENTATION");

        // print upgrade config
        console.log("ProxyAdmin:", proxyAdminAddress);
        console.log("Proxy:", proxyAddress);
        console.log("New Implementation:", newImplementation);

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);

        // Upgrade the proxy to the new implementation
        // Using upgradeAndCall with empty data (no initialization needed)
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(proxyAddress)),
            newImplementation,
            "" // empty data - no initialization function to call
        );

        console.log("--------------------------------");
        console.log("Upgrade successful!");
        console.log("Proxy", proxyAddress, "now points to implementation", newImplementation);

        vm.stopBroadcast();
    }
}
