// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {SBTSale} from "../src/SBTSale.sol";

/**
 * @title DeploySBTSale
 * @notice Deploys the SBTSale implementation and proxy.
 */
contract DeploySBTSale is Script {
    function run() external returns (TransparentUpgradeableProxy proxy) {
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
        address admin = vm.envAddress("P2E_ADMIN");

        // print deployment config
        console.log("POAS Minter:", poasMinter);
        console.log("Liquidity Pool:", liquidityPool);
        console.log("LP Recipient:", lpRecipient);
        console.log("Revenue Recipient:", revenueRecipient);
        console.log("SMP Base Price:", smpBasePrice);
        console.log("SMP Burn Ratio:", smpBurnRatio);
        console.log("SMP Liquidity Ratio:", smpLiquidityRatio);
        console.log("Admin:", admin);

        SBTSale implementation = new SBTSale(
            poasMinter,
            liquidityPool,
            lpRecipient,
            revenueRecipient,
            smpBasePrice,
            smpBurnRatio,
            smpLiquidityRatio
        );

        // Note: TransparentUpgradeableProxy automatically deploys a new ProxyAdmin contract
        // The second parameter (admin) becomes the owner of that ProxyAdmin contract
        // The proxy's admin (stored in ERC1967 admin slot) will be the ProxyAdmin contract address
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin, // This becomes the owner of the newly deployed ProxyAdmin contract
            abi.encodeWithSelector(SBTSale.initialize.selector, admin)
        );

        // print deployment result
        bytes32 ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        address proxyAdminContract = address(uint160(uint256(vm.load(address(proxy), ADMIN_SLOT))));
        console.log("--------------------------------");
        console.log("SBTSale(implementation):", address(implementation));
        console.log("ProxyAdmin contract:", proxyAdminContract);
        console.log("ProxyAdmin owner:", admin);
        console.log("Proxy:", address(proxy));

        vm.stopBroadcast();
    }
}
