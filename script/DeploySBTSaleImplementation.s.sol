// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {SBTSale} from "../src/SBTSale.sol";

/**
 * @title DeploySBTSaleImplementation
 * @notice Deploys only the SBTSale implementation contract (for upgrades).
 */
contract DeploySBTSaleImplementation is Script {
    function run() external returns (SBTSale implementation) {
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

        address poasMinter = vm.envAddress("P2E_POAS_MINTER");
        address liquidityPool = vm.envAddress("P2E_LIQUIDITY_POOL");
        address lpRecipient = vm.envAddress("P2E_LP_RECIPIENT");
        address revenueRecipient = vm.envAddress("P2E_REVENUE_RECIPIENT");
        uint256 smpBasePrice = vm.envUint("P2E_SMP_BASE_PRICE");
        uint256 smpBurnRatio = vm.envUint("P2E_SMP_BURN_RATIO");
        uint256 smpLiquidityRatio = vm.envUint("P2E_SMP_LIQUIDITY_RATIO");

        // print deployment config
        console.log("POAS Minter:", poasMinter);
        console.log("Liquidity Pool:", liquidityPool);
        console.log("LP Recipient:", lpRecipient);
        console.log("Revenue Recipient:", revenueRecipient);
        console.log("SMP Base Price:", smpBasePrice);
        console.log("SMP Burn Ratio:", smpBurnRatio);
        console.log("SMP Liquidity Ratio:", smpLiquidityRatio);

        implementation = new SBTSale(
            poasMinter,
            liquidityPool,
            lpRecipient,
            revenueRecipient,
            smpBasePrice,
            smpBurnRatio,
            smpLiquidityRatio
        );

        // print deployment result
        console.log("--------------------------------");
        console.log("SBTSale Implementation:", address(implementation));

        vm.stopBroadcast();
    }
}
