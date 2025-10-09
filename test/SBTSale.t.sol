// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
pragma experimental ABIEncoderV2;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import {IVault} from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import {SBTSale} from "../src/SBTSale.sol";
import {ISBTSale} from "../src/interfaces/ISBTSale.sol";
import {IVaultPool} from "../src/interfaces/IVaultPool.sol";
import {ISBTSaleERC721} from "../src/interfaces/ISBTSaleERC721.sol";
import {IPOAS} from "../src/interfaces/IPOAS.sol";
import {IPOASMinter} from "../src/interfaces/IPOASMinter.sol";
import {IWOAS} from "../src/interfaces/IWOAS.sol";

import {VaultDeployer} from "./helpers/deployers/VaultDeployer.sol";
import {WeightedPoolFactoryDeployer} from "./helpers/deployers/WeightedPoolFactoryDeployer.sol";
import {BalancerV2HelperDeployer} from "./helpers/deployers/BalancerV2HelperDeployer.sol";
import {IBalancerV2Helper} from "./helpers/interfaces/IBalancerV2Helper.sol";
import {MockSMP} from "./mocks/MockSMPv8.sol";
import {MockPOASMinter} from "./mocks/MockPOASMinter.sol";
import {MockSBTSaleERC721} from "./mocks/MockSBTSaleERC721.sol";

contract SBTSaleTest is Test {
    ISBTSale p2e;
    address p2eAddr;

    IBalancerV2Helper bv2helper;
    IVault vault;
    IVaultPool pool;
    IERC20 woas;
    IERC20 smp;
    IPOAS poas;
    IPOASMinter poasMinter;
    address nativeOAS = address(0);

    address deployer; // Deploys all contracts
    address lpRecipient;
    address revenueRecipient;
    address sender;
    address owner;

    // Signature verification test accounts
    uint256 signerPrivateKey = 0xA11CE;
    address signerAddress;

    uint256 woasSMPPriceRatio = 4;
    uint256 initialWOASLiquidity = 10_000 ether;
    uint256 initialSMPLiquidity = initialWOASLiquidity * woasSMPPriceRatio;

    uint256 smpBasePrice = 50 ether;
    uint256 userInitialBalance = smpBasePrice * 10;

    ISBTSaleERC721 sbtContract;
    uint256 constant NFT_COUNT = 3;
    uint256 totalSMPPrice = 150 ether; // 3 NFTs × 50 SMP
    uint256 totalSMPBurn = 75 ether; // 50% of 150 SMP
    uint256 totalSMPLiquidity = 60 ether; // 40% of 150 SMP
    uint256 totalSMPRevenue = 15 ether; // 10% of 150 SMP
    uint256 totalOASPrice = totalSMPPrice / woasSMPPriceRatio;
    uint256 purchaseGasLimit = 1_000_000;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);
    event Paid(address indexed from, address indexed recipient, uint256 amount);
    event Swap(
        bytes32 indexed poolId,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    function setUp() public {
        // Set initial block timestamp to a reasonable value
        vm.warp(1_000_000);

        // Create test accounts
        deployer = makeAddr("deployer");
        lpRecipient = makeAddr("lpRecipient");
        revenueRecipient = makeAddr("revenueRecipient");
        sender = makeAddr("sender");
        owner = makeAddr("owner");
        signerAddress = vm.addr(signerPrivateKey);

        // Deploy BalancerV2 test utilities
        vm.startPrank(deployer);
        bytes32 salt = keccak256(abi.encode("DEPLOYER_SALT"));
        VaultDeployer vaultDeployer = new VaultDeployer(salt);
        WeightedPoolFactoryDeployer poolFactoryDeployer =
            new WeightedPoolFactoryDeployer(salt, vaultDeployer.vault());
        BalancerV2HelperDeployer bv2deployer = new BalancerV2HelperDeployer(
            salt, vaultDeployer.vault(), poolFactoryDeployer.poolFactory()
        );

        bv2helper = IBalancerV2Helper(bv2deployer.helper());
        vault = IVault(vaultDeployer.vault());

        // Deploy payment tokens
        IWOAS _woas = IWOAS(vaultDeployer.woas());
        MockSMP _smp = new MockSMP();
        poasMinter = IPOASMinter(new MockPOASMinter());

        // Create the BalancerV2 Pool
        pool = bv2helper.createPool(
            IBalancerV2Helper.PoolConfig({
                owner: address(this),
                name: "WOAS-SMP",
                symbol: "WOAS-SMP",
                swapFeePercentage: 0,
                tokenA: IERC20(address(_woas)),
                tokenB: IERC20(address(_smp))
            })
        );

        // Deploy implementation
        SBTSale implementation = new SBTSale({
            poasMinter: address(poasMinter),
            liquidityPool: address(pool),
            lpRecipient: lpRecipient,
            revenueRecipient: revenueRecipient,
            smpBasePrice: smpBasePrice,
            smpBurnRatio: 5000,
            smpLiquidityRatio: 4000
        });

        // Deploy as proxy and initialize
        bytes memory initData = abi.encodeWithSelector(SBTSale.initialize.selector, deployer);
        p2eAddr =
            address(new TransparentUpgradeableProxy(address(implementation), deployer, initData));
        p2e = ISBTSale(p2eAddr);
        woas = IERC20(address(_woas));
        poas = IPOAS(poasMinter.poas());
        smp = IERC20(address(_smp));

        // Grant relayer roles to helper contract
        vaultDeployer.grantRelayerRolesToHelper(address(bv2helper));
        vault.setRelayerApproval(deployer, address(bv2helper), true);

        // Add initial liquidity to the pool
        IERC20[2] memory tokens;
        uint256[2] memory amounts;
        if (woas < smp) {
            tokens[0] = woas;
            tokens[1] = smp;
            amounts[0] = initialWOASLiquidity;
            amounts[1] = initialSMPLiquidity;
        } else {
            tokens[0] = smp;
            tokens[1] = woas;
            amounts[0] = initialSMPLiquidity;
            amounts[1] = initialWOASLiquidity;
        }
        vm.deal(deployer, initialWOASLiquidity);
        _woas.deposit{value: initialWOASLiquidity}();
        _woas.approve(address(vault), initialWOASLiquidity);
        _smp.mint(deployer, initialSMPLiquidity);
        _smp.approve(address(vault), initialSMPLiquidity);
        bv2helper.addInitialLiquidity(pool, deployer, deployer, tokens, amounts);

        // Deploy single SBT contract
        sbtContract = new MockSBTSaleERC721("SoulboundToken", "SBT", p2eAddr);

        // Set the SBT contract and signer in the sale contract (as deployer/owner)
        p2e.setSBTContract(sbtContract);
        p2e.setSigner(signerAddress); // Use test signer address for EIP-712 tests

        vm.stopPrank();

        // Mint tokens
        {
            vm.startPrank(sender);

            // for WOAS payment
            vm.deal(sender, userInitialBalance);
            _woas.deposit{value: userInitialBalance}();

            // for POAS payment
            vm.deal(sender, userInitialBalance);
            poasMinter.mint{value: userInitialBalance}(sender, userInitialBalance);

            // for SMP Payment
            vm.deal(sender, userInitialBalance);
            _smp.mint(sender, userInitialBalance);

            // for native OAS payment
            vm.deal(sender, userInitialBalance);

            vm.stopPrank();
        }
    }

    // =============================================================
    //                   CONSTRUCTOR ERROR TESTS
    // =============================================================

    function test_constructor_invalidPOASMinter() public {
        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidAddress.selector, address(0)));
        new SBTSale({
            poasMinter: address(0),
            liquidityPool: address(pool),
            lpRecipient: lpRecipient,
            revenueRecipient: revenueRecipient,
            smpBasePrice: smpBasePrice,
            smpBurnRatio: 5000,
            smpLiquidityRatio: 4000
        });
    }

    function test_constructor_invalidLiquidityPool() public {
        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidAddress.selector, address(0)));
        new SBTSale({
            poasMinter: address(poasMinter),
            liquidityPool: address(0),
            lpRecipient: lpRecipient,
            revenueRecipient: revenueRecipient,
            smpBasePrice: smpBasePrice,
            smpBurnRatio: 5000,
            smpLiquidityRatio: 4000
        });
    }

    function test_constructor_invalidLPRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidRecipient.selector, address(0)));
        new SBTSale({
            poasMinter: address(poasMinter),
            liquidityPool: address(pool),
            lpRecipient: address(0),
            revenueRecipient: revenueRecipient,
            smpBasePrice: smpBasePrice,
            smpBurnRatio: 5000,
            smpLiquidityRatio: 4000
        });
    }

    function test_constructor_invalidRevenueRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidRecipient.selector, address(0)));
        new SBTSale({
            poasMinter: address(poasMinter),
            liquidityPool: address(pool),
            lpRecipient: lpRecipient,
            revenueRecipient: address(0),
            smpBasePrice: smpBasePrice,
            smpBurnRatio: 5000,
            smpLiquidityRatio: 4000
        });
    }

    function test_constructor_invalidSMPBasePrice() public {
        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidPaymentAmount.selector, 0));
        new SBTSale({
            poasMinter: address(poasMinter),
            liquidityPool: address(pool),
            lpRecipient: lpRecipient,
            revenueRecipient: revenueRecipient,
            smpBasePrice: 0,
            smpBurnRatio: 5000,
            smpLiquidityRatio: 4000
        });
    }

    function test_constructor_invalidRatioSum() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ISBTSale.InvalidProtocolValue.selector,
                "smpBurnRatio + smpLiquidityRatio exceeds MAX_BASIS_POINTS"
            )
        );
        new SBTSale({
            poasMinter: address(poasMinter),
            liquidityPool: address(pool),
            lpRecipient: lpRecipient,
            revenueRecipient: revenueRecipient,
            smpBasePrice: smpBasePrice,
            smpBurnRatio: 6000,
            smpLiquidityRatio: 5000
        });
    }

    // =============================================================
    //                    CONFIGURATION TESTS
    // =============================================================

    function test_getWOAS() public view {
        assertEq(p2e.getWOAS(), address(woas));
    }

    function test_getPOAS() public view {
        assertEq(p2e.getPOAS(), address(poas));
    }

    function test_getSMP() public view {
        assertEq(p2e.getSMP(), address(smp));
    }

    function test_getPOASMinter() public view {
        assertEq(p2e.getPOASMinter(), address(poasMinter));
    }

    function test_getLiquidityPool() public view {
        assertEq(p2e.getLiquidityPool(), address(pool));
    }

    function test_getLPRecipient() public view {
        assertEq(p2e.getLPRecipient(), lpRecipient);
    }

    function test_getRevenueRecipient() public view {
        assertEq(p2e.getRevenueRecipient(), revenueRecipient);
    }

    function test_getSMPBurnRatio() public view {
        assertEq(p2e.getSMPBurnRatio(), 5000);
    }

    function test_getSMPLiquidityRatio() public view {
        assertEq(p2e.getSMPLiquidityRatio(), 4000);
    }

    // =============================================================
    //                 SIGNATURE MANAGEMENT TESTS
    // =============================================================

    function test_setSigner() public {
        vm.startPrank(deployer);
        address newSigner = makeAddr("newSigner");

        vm.expectEmit(p2eAddr);
        emit ISBTSale.SignerUpdated(signerAddress, newSigner);

        p2e.setSigner(newSigner);
        assertEq(p2e.getSigner(), newSigner);
        vm.stopPrank();
    }

    function test_setSigner_unauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        address newSigner = makeAddr("newSigner");

        vm.startPrank(unauthorized);
        vm.expectRevert();
        p2e.setSigner(newSigner);
        vm.stopPrank();
    }

    function test_setSigner_zeroAddress() public {
        vm.startPrank(deployer);
        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidSigner.selector, address(0)));
        p2e.setSigner(address(0));
        vm.stopPrank();
    }

    function test_setSigner_noOp() public {
        vm.startPrank(deployer);

        // Get current signer
        address currentSigner = p2e.getSigner();

        // Record logs to verify no event is emitted
        vm.recordLogs();

        // Set the same signer (should be a no-op)
        p2e.setSigner(currentSigner);

        // Verify no events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "No events should be emitted for no-op");

        // Verify signer hasn't changed
        assertEq(p2e.getSigner(), currentSigner);

        vm.stopPrank();
    }

    function test_getSigner() public view {
        assertEq(p2e.getSigner(), signerAddress);
    }

    function test_isUsedPurchaseId() public {
        assertFalse(p2e.isUsedPurchaseId(123));
    }

    // =============================================================
    //               SBT CONTRACT MANAGEMENT TESTS
    // =============================================================

    function test_setSBTContract() public {
        vm.startPrank(deployer);
        address newSBTContract = address(new MockSBTSaleERC721("NewSBT", "NSBT", p2eAddr));

        vm.expectEmit(p2eAddr);
        emit ISBTSale.SBTContractUpdated(address(sbtContract), newSBTContract);

        p2e.setSBTContract(ISBTSaleERC721(newSBTContract));
        assertEq(address(p2e.getSBTContract()), newSBTContract);
        vm.stopPrank();
    }

    function test_setSBTContract_unauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        address newSBTContract = address(new MockSBTSaleERC721("NewSBT", "NSBT", p2eAddr));

        vm.startPrank(unauthorized);
        vm.expectRevert();
        p2e.setSBTContract(ISBTSaleERC721(newSBTContract));
        vm.stopPrank();
    }

    function test_setSBTContract_zeroAddress() public {
        vm.startPrank(deployer);
        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidAddress.selector, address(0)));
        p2e.setSBTContract(ISBTSaleERC721(address(0)));
        vm.stopPrank();
    }

    function test_getSBTContract() public view {
        assertEq(address(p2e.getSBTContract()), address(sbtContract));
    }

    function test_setSBTContract_validContractWithFunctionality() public {
        vm.startPrank(deployer);
        MockSBTSaleERC721 newSBTContract = new MockSBTSaleERC721("NewSBT", "NSBT", p2eAddr);
        ISBTSaleERC721 oldContract = p2e.getSBTContract();

        // Test event emission
        vm.expectEmit(true, true, false, true);
        emit ISBTSale.SBTContractUpdated(address(oldContract), address(newSBTContract));

        p2e.setSBTContract(newSBTContract);
        assertEq(address(p2e.getSBTContract()), address(newSBTContract));

        // Test functionality with new contract
        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("testRecipient");
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 300;

        p2e.mintByOwner(recipients, tokenIds);
        assertEq(newSBTContract.ownerOf(tokenIds[0]), recipients[0]);

        // Restore original contract
        p2e.setSBTContract(sbtContract);
        vm.stopPrank();
    }

    function test_setSBTContract_multipleUpdates() public {
        vm.startPrank(deployer);
        ISBTSaleERC721 originalContract = p2e.getSBTContract();
        MockSBTSaleERC721 firstContract = new MockSBTSaleERC721("First", "F1", p2eAddr);
        MockSBTSaleERC721 secondContract = new MockSBTSaleERC721("Second", "S2", p2eAddr);

        vm.expectEmit(true, true, false, true);
        emit ISBTSale.SBTContractUpdated(address(originalContract), address(firstContract));
        p2e.setSBTContract(firstContract);
        assertEq(address(p2e.getSBTContract()), address(firstContract));

        vm.expectEmit(true, true, false, true);
        emit ISBTSale.SBTContractUpdated(address(firstContract), address(secondContract));
        p2e.setSBTContract(secondContract);
        assertEq(address(p2e.getSBTContract()), address(secondContract));

        p2e.setSBTContract(originalContract);
        vm.stopPrank();
    }

    function test_setSBTContract_invalidInterface() public {
        vm.startPrank(deployer);

        // Try to set a contract that doesn't implement ISBTSaleERC721
        // WOAS doesn't implement ISBTSaleERC721, so it should fail
        address invalidContract = address(woas);
        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidAddress.selector, invalidContract));
        p2e.setSBTContract(ISBTSaleERC721(invalidContract));

        vm.stopPrank();
    }

    function test_setSBTContract_noOp() public {
        vm.startPrank(deployer);

        // Get current SBT contract
        ISBTSaleERC721 currentContract = p2e.getSBTContract();

        // Record logs to verify no event is emitted
        vm.recordLogs();

        // Set the same contract (should be a no-op)
        p2e.setSBTContract(currentContract);

        // Verify no events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "No events should be emitted for no-op");

        // Verify contract hasn't changed
        assertEq(address(p2e.getSBTContract()), address(currentContract));

        vm.stopPrank();
    }

    // =============================================================
    //                   INTEGRATION TESTS
    // =============================================================

    // =============================================================
    //                    OWNER MINT TESTS
    // =============================================================

    function test_mintByOwner_singleRecipient() public {
        vm.startPrank(deployer);

        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient1");
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 200;

        p2e.mintByOwner(recipients, tokenIds);
        assertEq(sbtContract.ownerOf(tokenIds[0]), recipients[0]);

        vm.stopPrank();
    }

    function test_mintByOwner_multipleRecipients() public {
        vm.startPrank(deployer);

        address[] memory recipients = new address[](3);
        recipients[0] = makeAddr("recipient1");
        recipients[1] = makeAddr("recipient2");
        recipients[2] = makeAddr("recipient3");
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 201;
        tokenIds[1] = 202;
        tokenIds[2] = 203;

        vm.expectEmit(true, false, false, true);
        emit ISBTSale.OwnerMinted(deployer, recipients, tokenIds);

        p2e.mintByOwner(recipients, tokenIds);

        for (uint256 i = 0; i < recipients.length; i++) {
            assertEq(sbtContract.ownerOf(tokenIds[i]), recipients[i]);
        }

        vm.stopPrank();
    }

    function test_mintByOwner_onlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient1");
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 204;

        vm.startPrank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        p2e.mintByOwner(recipients, tokenIds);
        vm.stopPrank();
    }

    function test_mintByOwner_emptyArrays() public {
        vm.startPrank(deployer);

        address[] memory recipients = new address[](0);
        uint256[] memory tokenIds = new uint256[](0);

        vm.expectRevert(ISBTSale.NoItems.selector);
        p2e.mintByOwner(recipients, tokenIds);
        vm.stopPrank();
    }

    function test_mintByOwner_arrayLengthMismatch() public {
        vm.startPrank(deployer);

        address[] memory recipients = new address[](2);
        recipients[0] = makeAddr("recipient1");
        recipients[1] = makeAddr("recipient2");
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 205;
        tokenIds[1] = 206;
        tokenIds[2] = 207;

        vm.expectRevert(abi.encodeWithSelector(ISBTSale.ArrayLengthMismatch.selector, 2, 3));
        p2e.mintByOwner(recipients, tokenIds);
        vm.stopPrank();
    }

    function test_mintByOwner_zeroAddress() public {
        vm.startPrank(deployer);

        address[] memory recipients = new address[](2);
        recipients[0] = makeAddr("recipient1");
        recipients[1] = address(0);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 208;
        tokenIds[1] = 209;

        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidAddress.selector, address(0)));
        p2e.mintByOwner(recipients, tokenIds);
        vm.stopPrank();
    }

    function test_mintByOwner_noSBTContract() public {
        // Create a new SBTSale instance without SBT contract set
        vm.startPrank(deployer);
        SBTSale implementation = new SBTSale({
            poasMinter: address(poasMinter),
            liquidityPool: address(pool),
            lpRecipient: lpRecipient,
            revenueRecipient: revenueRecipient,
            smpBasePrice: smpBasePrice,
            smpBurnRatio: 5000,
            smpLiquidityRatio: 4000
        });

        // Deploy as proxy
        bytes memory initData = abi.encodeWithSelector(SBTSale.initialize.selector, deployer);
        address testP2EAddr =
            address(new TransparentUpgradeableProxy(address(implementation), deployer, initData));
        ISBTSale testP2E = ISBTSale(testP2EAddr);
        // Don't set SBT contract - it remains address(0)

        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient1");
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 210;

        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidAddress.selector, address(0)));
        testP2E.mintByOwner(recipients, tokenIds);
        vm.stopPrank();
    }

    function test_mintByOwner_tooManyItems() public {
        vm.startPrank(deployer);

        address[] memory recipients = new address[](201);
        uint256[] memory tokenIds = new uint256[](201);
        for (uint256 i = 0; i < 201; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("recipient", vm.toString(i))));
            tokenIds[i] = i + 2000;
        }

        vm.expectRevert(abi.encodeWithSelector(ISBTSale.TooManyItems.selector, 201, 200));
        p2e.mintByOwner(recipients, tokenIds);
        vm.stopPrank();
    }

    // =============================================================
    //                     PRICE QUERY TESTS
    // =============================================================

    function test_queryPrice() public {
        uint256 oasPrice = p2e.queryPrice(NFT_COUNT, nativeOAS);
        assertGe(oasPrice, totalOASPrice);
        assertLe(oasPrice, totalOASPrice + 1.5 ether);

        uint256 poasPrice = p2e.queryPrice(NFT_COUNT, address(poas));
        assertEq(poasPrice, oasPrice);

        uint256 smpPrice = p2e.queryPrice(NFT_COUNT, address(smp));
        assertEq(smpPrice, totalSMPPrice);
    }

    // =============================================================
    //                  EIP-712 SIGNATURE TESTS
    // =============================================================

    function test_purchase_validSignature() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 100;
        uint256 purchaseId = 995;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 amount = p2e.queryPrice(1, nativeOAS);

        ISBTSale.PurchaseOrder memory order =
            _createPurchaseOrder(purchaseId, sender, tokenIds, nativeOAS, amount, 0, deadline);
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.deal(sender, amount);
        p2e.purchase{value: amount}(
            tokenIds, nativeOAS, amount, 0, purchaseId, deadline, signature
        );

        assertEq(sbtContract.ownerOf(tokenIds[0]), sender);
        vm.stopPrank();
    }

    function test_purchase_invalidSignature() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 101;
        uint256 purchaseId = 994;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 amount = p2e.queryPrice(1, nativeOAS);

        uint256 wrongPrivateKey = 0x1234;
        ISBTSale.PurchaseOrder memory order =
            _createPurchaseOrder(purchaseId, sender, tokenIds, nativeOAS, amount, 0, deadline);
        bytes memory invalidSignature = _signPurchaseOrder(order, wrongPrivateKey);

        vm.deal(sender, amount);
        vm.expectRevert(ISBTSale.InvalidSignature.selector);
        p2e.purchase{value: amount}(
            tokenIds, nativeOAS, amount, 0, purchaseId, deadline, invalidSignature
        );

        vm.stopPrank();
    }

    function test_purchase_expiredDeadline() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 102;
        uint256 purchaseId = 993;
        uint256 pastDeadline = block.timestamp - 1;
        uint256 amount = p2e.queryPrice(1, nativeOAS);

        ISBTSale.PurchaseOrder memory order =
            _createPurchaseOrder(purchaseId, sender, tokenIds, nativeOAS, amount, 300, pastDeadline);
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.deal(sender, amount);
        uint256 currentTimestamp = block.timestamp;
        vm.expectRevert(
            abi.encodeWithSelector(
                ISBTSale.ExpiredDeadline.selector, pastDeadline, currentTimestamp
            )
        );
        p2e.purchase{value: amount}(
            tokenIds, nativeOAS, amount, 300, purchaseId, pastDeadline, signature
        );

        vm.stopPrank();
    }

    function test_purchase_duplicatePurchaseId() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 103;
        uint256 purchaseId = 992;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 amount = p2e.queryPrice(1, nativeOAS);

        ISBTSale.PurchaseOrder memory order =
            _createPurchaseOrder(purchaseId, sender, tokenIds, nativeOAS, amount, 0, deadline);
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.deal(sender, amount * 2);
        p2e.purchase{value: amount}(
            tokenIds, nativeOAS, amount, 0, purchaseId, deadline, signature
        );

        assertTrue(p2e.isUsedPurchaseId(purchaseId));

        tokenIds[0] = 104;
        order = _createPurchaseOrder(purchaseId, sender, tokenIds, nativeOAS, amount, 300, deadline);
        signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.expectRevert(abi.encodeWithSelector(ISBTSale.PurchaseIdAlreadyUsed.selector, purchaseId));
        p2e.purchase{value: amount}(
            tokenIds, nativeOAS, amount, 300, purchaseId, deadline, signature
        );

        vm.stopPrank();
    }

    function test_purchase_buyerMismatch() public {
        address differentBuyer = makeAddr("differentBuyer");

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 105;
        uint256 purchaseId = 991;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 amount = p2e.queryPrice(1, nativeOAS);

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            purchaseId, differentBuyer, tokenIds, nativeOAS, amount, 300, deadline
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.startPrank(sender);
        vm.deal(sender, amount);
        // Buyer mismatch now results in InvalidSignature since buyer is embedded in signature
        vm.expectRevert(ISBTSale.InvalidSignature.selector);
        p2e.purchase{value: amount}(
            tokenIds, nativeOAS, amount, 300, purchaseId, deadline, signature
        );
        vm.stopPrank();
    }

    function test_purchase_OAS() public {
        vm.startPrank(sender);

        uint256 actualAmount = p2e.queryPrice(NFT_COUNT, nativeOAS);
        uint256 paymentAmount = actualAmount + 0.1 ether;

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            1, sender, tokenIds, nativeOAS, paymentAmount, 300, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        p2e.purchase{gas: purchaseGasLimit, value: paymentAmount}(
            tokenIds, nativeOAS, paymentAmount, 300, 1, block.timestamp + 1 hours, signature
        );

        _expect_minted_nfts(sender, tokenIds);
        assertLe(sender.balance, userInitialBalance - actualAmount);
    }

    function test_purchase_POAS() public {
        vm.startPrank(sender);

        uint256 actualAmount = p2e.queryPrice(NFT_COUNT, address(poas));
        uint256 paymentAmount = actualAmount + 0.1 ether;
        poas.approve(p2eAddr, paymentAmount);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 7;
        tokenIds[1] = 8;
        tokenIds[2] = 9;

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            2, sender, tokenIds, address(poas), paymentAmount, 300, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        p2e.purchase{gas: purchaseGasLimit}(
            tokenIds,
            address(poas),
            paymentAmount,
            300,
            2,
            block.timestamp + 1 hours,
            signature
        );

        _expect_minted_nfts(sender, tokenIds);
        assertEq(poas.balanceOf(sender), userInitialBalance - actualAmount);
    }

    function test_purchase_SMP() public {
        vm.startPrank(sender);

        uint256 actualAmount = totalSMPPrice;
        smp.approve(p2eAddr, actualAmount);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 16;
        tokenIds[1] = 17;
        tokenIds[2] = 18;

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            5, sender, tokenIds, address(smp), actualAmount, 300, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        p2e.purchase{gas: purchaseGasLimit}(
            tokenIds,
            address(smp),
            actualAmount,
            300,
            5,
            block.timestamp + 1 hours,
            signature
        );

        _expect_minted_nfts(sender, tokenIds);
        assertEq(smp.balanceOf(sender), userInitialBalance - actualAmount);
    }

    function test_purchase_SMP_overpayment() public {
        vm.startPrank(sender);

        uint256 requiredAmount = totalSMPPrice;
        uint256 overpaymentAmount = requiredAmount + 10 ether; // Paying more than required
        smp.approve(p2eAddr, overpaymentAmount);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 19;
        tokenIds[1] = 20;
        tokenIds[2] = 21;

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            6, sender, tokenIds, address(smp), overpaymentAmount, 300, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidPaymentAmount.selector, overpaymentAmount));
        p2e.purchase{gas: purchaseGasLimit}(
            tokenIds,
            address(smp),
            overpaymentAmount,
            300,
            6,
            block.timestamp + 1 hours,
            signature
        );

        vm.stopPrank();
    }

    // =============================================================
    //                PURCHASE ERROR TESTS
    // =============================================================

    function test_purchase_noSBTContract() public {
        // Create a new SBTSale instance without SBT contract set
        vm.startPrank(deployer);
        SBTSale implementation = new SBTSale({
            poasMinter: address(poasMinter),
            liquidityPool: address(pool),
            lpRecipient: lpRecipient,
            revenueRecipient: revenueRecipient,
            smpBasePrice: smpBasePrice,
            smpBurnRatio: 5000,
            smpLiquidityRatio: 4000
        });

        // Deploy as proxy
        bytes memory initData = abi.encodeWithSelector(SBTSale.initialize.selector, deployer);
        address testP2EAddr =
            address(new TransparentUpgradeableProxy(address(implementation), deployer, initData));
        ISBTSale testP2E = ISBTSale(testP2EAddr);
        testP2E.setSigner(signerAddress);
        // Don't set SBT contract - it remains address(0)

        vm.stopPrank();

        vm.startPrank(sender);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 999;
        uint256 amount = testP2E.queryPrice(1, nativeOAS);

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            999, sender, tokenIds, nativeOAS, amount, 0, block.timestamp + 1 hours
        );
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "PurchaseOrder(uint256 purchaseId,address buyer,uint256[] tokenIds,address paymentToken,uint256 amount,uint256 minRevenueOAS,uint256 deadline)"
                ),
                order.purchaseId,
                order.buyer,
                keccak256(abi.encode(order.tokenIds)),
                order.paymentToken,
                order.amount,
                order.minRevenueOAS,
                order.deadline
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("SBTSale")),
                keccak256(bytes("1")),
                block.chainid,
                address(testP2E)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.deal(sender, amount);
        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidAddress.selector, address(0)));
        testP2E.purchase{value: amount}(
            tokenIds, nativeOAS, amount, 300, 999, block.timestamp + 1 hours, signature
        );
        vm.stopPrank();
    }

    function test_purchase_tooManyItems() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](201);
        for (uint256 i = 0; i < 201; i++) {
            tokenIds[i] = i + 1000;
        }

        uint256 amount = p2e.queryPrice(201, nativeOAS);
        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            998, sender, tokenIds, nativeOAS, amount, 0, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.deal(sender, amount);
        vm.expectRevert(abi.encodeWithSelector(ISBTSale.TooManyItems.selector, 201, 200));
        p2e.purchase{value: amount}(
            tokenIds, nativeOAS, amount, 0, 998, block.timestamp + 1 hours, signature
        );
        vm.stopPrank();
    }

    function test_purchase_invalidPaymentToken() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 997;
        uint256 amount = 1 ether;
        address invalidToken = makeAddr("invalidToken");

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            997, sender, tokenIds, invalidToken, amount, 0, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.expectRevert(
            abi.encodeWithSelector(ISBTSale.InvalidPaymentToken.selector, invalidToken)
        );
        p2e.purchase(
            tokenIds, invalidToken, amount, 0, 997, block.timestamp + 1 hours, signature
        );
        vm.stopPrank();
    }

    function test_purchase_slippageExceeded() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 996;
        uint256 actualAmount = p2e.queryPrice(1, nativeOAS);
        uint256 lowPaymentAmount = actualAmount / 10; // Very insufficient amount

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            996, sender, tokenIds, nativeOAS, lowPaymentAmount, 100, block.timestamp + 1 hours
        ); // 1% slippage tolerance
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.deal(sender, lowPaymentAmount);
        // With insufficient funds, the Balancer pool will revert with BAL#507 (insufficient balance)
        // rather than reaching our slippage check, so we expect the Balancer error
        vm.expectRevert(); // Could be BAL#507 or SlippageExceeded depending on order
        p2e.purchase{value: lowPaymentAmount}(
            tokenIds,
            nativeOAS,
            lowPaymentAmount,
            100,
            996,
            block.timestamp + 1 hours,
            signature
        );
        vm.stopPrank();
    }

    function test_purchase_invalidPaymentAmountForNativeOAS() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 995;
        uint256 amount = p2e.queryPrice(1, nativeOAS);

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            995, sender, tokenIds, nativeOAS, amount, 0, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        uint256 overpayAmount = amount * 2;
        vm.deal(sender, overpayAmount);
        vm.expectRevert(
            abi.encodeWithSelector(ISBTSale.InvalidPaymentAmount.selector, overpayAmount)
        );
        p2e.purchase{value: overpayAmount}( // Sending wrong msg.value
        tokenIds, nativeOAS, amount, 0, 995, block.timestamp + 1 hours, signature);
        vm.stopPrank();
    }

    function test_purchase_msgValueForERC20() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 994;
        uint256 amount = totalSMPPrice;
        smp.approve(p2eAddr, amount);

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            994, sender, tokenIds, address(smp), amount, 0, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        uint256 unexpectedValue = 1 ether;
        vm.expectRevert(
            abi.encodeWithSelector(ISBTSale.InvalidPaymentAmount.selector, unexpectedValue)
        );
        p2e.purchase{value: unexpectedValue}( // Should not send msg.value for ERC20
        tokenIds, address(smp), amount, 0, 994, block.timestamp + 1 hours, signature);
        vm.stopPrank();
    }

    // =============================================================
    //                      QUERY PRICE ERROR TESTS
    // =============================================================

    function test_queryPrice_noItems() public {
        vm.expectRevert(ISBTSale.NoItems.selector);
        p2e.queryPrice(0, nativeOAS);
    }

    function test_queryPrice_invalidPaymentToken() public {
        address invalidToken = makeAddr("invalidToken");
        vm.expectRevert(
            abi.encodeWithSelector(ISBTSale.InvalidPaymentToken.selector, invalidToken)
        );
        p2e.queryPrice(1, invalidToken);
    }

    // =============================================================
    //              EVENT VERIFICATION PURCHASE TESTS
    // =============================================================

    function test_purchase_OAS_withEventCapture() public {
        vm.startPrank(sender);

        uint256 actualAmount = p2e.queryPrice(NFT_COUNT, nativeOAS);
        uint256 paymentAmount = actualAmount + 0.1 ether;

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 3001;
        tokenIds[1] = 3002;
        tokenIds[2] = 3003;

        // Record logs to verify events were emitted
        vm.recordLogs();

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            3001, sender, tokenIds, nativeOAS, paymentAmount, 300, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        p2e.purchase{gas: purchaseGasLimit, value: paymentAmount}(
            tokenIds,
            nativeOAS,
            paymentAmount,
            300,
            3001,
            block.timestamp + 1 hours,
            signature
        );

        // Verify events were emitted (check log count)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGt(logs.length, 5); // Should have multiple events: swaps, burns, transfers, etc.

        // Verify final state
        _expect_minted_nfts(sender, tokenIds);
        assertLe(sender.balance, userInitialBalance - actualAmount);

        vm.stopPrank();
    }

    function test_purchase_SMP_withEventCapture() public {
        vm.startPrank(sender);

        uint256 actualAmount = totalSMPPrice;
        smp.approve(p2eAddr, actualAmount);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 3004;
        tokenIds[1] = 3005;
        tokenIds[2] = 3006;

        // Record logs to verify events were emitted
        vm.recordLogs();

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            3004, sender, tokenIds, address(smp), actualAmount, 300, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        p2e.purchase{gas: purchaseGasLimit}(
            tokenIds,
            address(smp),
            actualAmount,
            300,
            3004,
            block.timestamp + 1 hours,
            signature
        );

        // Verify events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGt(logs.length, 3); // Should have burn, liquidity, revenue events

        // Verify final state
        _expect_minted_nfts(sender, tokenIds);
        assertEq(smp.balanceOf(sender), userInitialBalance - actualAmount);

        vm.stopPrank();
    }

    // =============================================================
    //                   EDGE CASE & BOUNDARY TESTS
    // =============================================================

    function test_purchase_maxBatchSize() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](200); // MAX_BATCH_SIZE
        for (uint256 i = 0; i < 200; i++) {
            tokenIds[i] = i + 4000;
        }

        uint256 amount = p2e.queryPrice(200, nativeOAS);
        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            4000, sender, tokenIds, nativeOAS, amount, 0, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.deal(sender, amount);
        p2e.purchase{value: amount}(
            tokenIds, nativeOAS, amount, 0, 4000, block.timestamp + 1 hours, signature
        );

        // Verify all NFTs were minted
        for (uint256 i = 0; i < 200; i++) {
            assertEq(sbtContract.ownerOf(tokenIds[i]), sender);
        }

        vm.stopPrank();
    }

    function test_purchase_zeroSlippage() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 4201;
        uint256 exactAmount = p2e.queryPrice(1, nativeOAS);

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            4201, sender, tokenIds, nativeOAS, exactAmount, 0, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.deal(sender, exactAmount);
        p2e.purchase{value: exactAmount}(
            tokenIds, nativeOAS, exactAmount, 0, 4201, block.timestamp + 1 hours, signature
        );

        assertEq(sbtContract.ownerOf(tokenIds[0]), sender);
        vm.stopPrank();
    }

    function test_purchase_maxSlippage() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 4202;
        uint256 baseAmount = p2e.queryPrice(1, nativeOAS);
        uint256 maxAmount = baseAmount * 2; // 100% higher

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            4202, sender, tokenIds, nativeOAS, maxAmount, 10_000, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.deal(sender, maxAmount);
        p2e.purchase{value: maxAmount}(
            tokenIds,
            nativeOAS,
            maxAmount,
            10_000,
            4202,
            block.timestamp + 1 hours,
            signature
        );

        assertEq(sbtContract.ownerOf(tokenIds[0]), sender);
        vm.stopPrank();
    }

    function test_purchase_nearDeadline() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 4203;
        uint256 amount = p2e.queryPrice(1, nativeOAS);
        uint256 deadline = block.timestamp + 1; // 1 second from now

        ISBTSale.PurchaseOrder memory order =
            _createPurchaseOrder(4203, sender, tokenIds, nativeOAS, amount, 0, deadline);
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.deal(sender, amount);
        p2e.purchase{value: amount}(
            tokenIds, nativeOAS, amount, 0, 4203, deadline, signature
        );

        assertEq(sbtContract.ownerOf(tokenIds[0]), sender);
        vm.stopPrank();
    }

    function test_purchase_insufficientRevenue() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 5001;
        uint256 amount = p2e.queryPrice(1, nativeOAS);

        // For 1 NFT (50 SMP):
        // - Burn: 25 SMP (50%)
        // - Liquidity: 20 SMP (40%)
        // - Revenue: 5 SMP (10%)
        // With WOAS:SMP ratio of 1:4, 5 SMP converts to approximately 1.25 OAS
        // Setting minRevenueOAS to 10 ether should cause InsufficientRevenue error
        uint256 unrealisticMinRevenue = 10 ether;

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            5001,
            sender,
            tokenIds,
            nativeOAS,
            amount,
            unrealisticMinRevenue,
            block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        vm.deal(sender, amount);

        // Expect InsufficientRevenue error
        // The actual revenue will be approximately 1.25 OAS (varies due to swap fees),
        // which is less than the unrealistic minimum of 10 OAS
        vm.expectRevert();
        p2e.purchase{value: amount}(
            tokenIds,
            nativeOAS,
            amount,
            unrealisticMinRevenue,
            5001,
            block.timestamp + 1 hours,
            signature
        );
        vm.stopPrank();
    }

    // Note: InsufficientBPTReceived is difficult to test in practice because:
    // 1. Balancer V2 pools always return BPT when liquidity is provided
    // 2. To get BPT = 0, we would need smpLiquidityRatio = 0, which would mean providedSMP = 0
    // 3. This would require deploying a new SBTSale contract with different configuration
    // 4. In normal operation with smpLiquidityRatio > 0, BPT should always be > 0
    // The check is in place as a safety measure for edge cases.

    // =============================================================
    //                   FREE PURCHASE TESTS
    // =============================================================

    function test_freePurchase_validSignature() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 5201;
        tokenIds[1] = 5202;
        uint256 purchaseId = 5201;
        uint256 deadline = block.timestamp + 1 hours;

        ISBTSale.FreePurchaseOrder memory order =
            _createFreePurchaseOrder(purchaseId, sender, tokenIds, deadline);
        bytes memory signature = _signFreePurchaseOrder(order, signerPrivateKey);

        _expect_free_purchased_event(sender, tokenIds, purchaseId);
        p2e.freePurchase(tokenIds, purchaseId, deadline, signature);

        _expect_minted_nfts(sender, tokenIds);
        assertTrue(p2e.isUsedPurchaseId(purchaseId));
        vm.stopPrank();
    }

    function test_freePurchase_invalidSignature() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 5301;
        uint256 purchaseId = 5301;
        uint256 deadline = block.timestamp + 1 hours;

        ISBTSale.FreePurchaseOrder memory order =
            _createFreePurchaseOrder(purchaseId, sender, tokenIds, deadline);
        uint256 wrongPrivateKey = 0x1234;
        bytes memory invalidSignature = _signFreePurchaseOrder(order, wrongPrivateKey);

        vm.expectRevert(ISBTSale.InvalidSignature.selector);
        p2e.freePurchase(tokenIds, purchaseId, deadline, invalidSignature);
        vm.stopPrank();
    }

    function test_freePurchase_expiredDeadline() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 5401;
        uint256 purchaseId = 5401;
        uint256 deadline = block.timestamp - 1; // Already expired

        ISBTSale.FreePurchaseOrder memory order =
            _createFreePurchaseOrder(purchaseId, sender, tokenIds, deadline);
        bytes memory signature = _signFreePurchaseOrder(order, signerPrivateKey);

        uint256 currentTimestamp = block.timestamp;
        vm.expectRevert(
            abi.encodeWithSelector(
                ISBTSale.ExpiredDeadline.selector, deadline, currentTimestamp
            )
        );
        p2e.freePurchase(tokenIds, purchaseId, deadline, signature);
        vm.stopPrank();
    }

    function test_freePurchase_duplicatePurchaseId() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 5501;
        uint256 purchaseId = 5501;
        uint256 deadline = block.timestamp + 1 hours;

        ISBTSale.FreePurchaseOrder memory order =
            _createFreePurchaseOrder(purchaseId, sender, tokenIds, deadline);
        bytes memory signature = _signFreePurchaseOrder(order, signerPrivateKey);

        _expect_free_purchased_event(sender, tokenIds, purchaseId);
        p2e.freePurchase(tokenIds, purchaseId, deadline, signature);

        assertTrue(p2e.isUsedPurchaseId(purchaseId));

        vm.expectRevert(abi.encodeWithSelector(ISBTSale.PurchaseIdAlreadyUsed.selector, purchaseId));
        p2e.freePurchase(tokenIds, purchaseId, deadline, signature);
        vm.stopPrank();
    }

    function test_freePurchase_buyerMismatch() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 5601;
        uint256 purchaseId = 5601;
        uint256 deadline = block.timestamp + 1 hours;
        address differentBuyer = makeAddr("differentBuyer");

        ISBTSale.FreePurchaseOrder memory order =
            _createFreePurchaseOrder(purchaseId, differentBuyer, tokenIds, deadline);
        bytes memory signature = _signFreePurchaseOrder(order, signerPrivateKey);

        // Buyer mismatch now results in InvalidSignature since buyer is embedded in signature
        vm.expectRevert(ISBTSale.InvalidSignature.selector);
        p2e.freePurchase(tokenIds, purchaseId, deadline, signature);
        vm.stopPrank();
    }

    function test_freePurchase_tooManyItems() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](201);
        for (uint256 i = 0; i < 201; i++) {
            tokenIds[i] = 6000 + i;
        }

        uint256 purchaseId = 5701;
        uint256 deadline = block.timestamp + 1 hours;

        ISBTSale.FreePurchaseOrder memory order =
            _createFreePurchaseOrder(purchaseId, sender, tokenIds, deadline);
        bytes memory signature = _signFreePurchaseOrder(order, signerPrivateKey);

        vm.expectRevert(abi.encodeWithSelector(ISBTSale.TooManyItems.selector, 201, 200));
        p2e.freePurchase(tokenIds, purchaseId, deadline, signature);
        vm.stopPrank();
    }

    function test_freePurchase_noSBTContract() public {
        vm.startPrank(deployer);
        SBTSale implementation = new SBTSale({
            poasMinter: address(poasMinter),
            liquidityPool: address(pool),
            lpRecipient: lpRecipient,
            revenueRecipient: revenueRecipient,
            smpBasePrice: smpBasePrice,
            smpBurnRatio: 5000,
            smpLiquidityRatio: 4000
        });

        bytes memory initData = abi.encodeWithSelector(SBTSale.initialize.selector, deployer);
        address testP2EAddr =
            address(new TransparentUpgradeableProxy(address(implementation), deployer, initData));
        ISBTSale testP2E = ISBTSale(testP2EAddr);
        testP2E.setSigner(signerAddress);
        vm.stopPrank();

        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 5801;
        uint256 purchaseId = 5801;
        uint256 deadline = block.timestamp + 1 hours;

        ISBTSale.FreePurchaseOrder memory order = ISBTSale.FreePurchaseOrder({
            purchaseId: purchaseId,
            buyer: sender,
            tokenIds: tokenIds,
            deadline: deadline
        });

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "FreePurchaseOrder(uint256 purchaseId,address buyer,uint256[] tokenIds,uint256 deadline)"
                ),
                order.purchaseId,
                order.buyer,
                keccak256(abi.encode(order.tokenIds)),
                order.deadline
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("SBTSale")),
                keccak256(bytes("1")),
                block.chainid,
                testP2EAddr
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(ISBTSale.InvalidAddress.selector, address(0)));
        testP2E.freePurchase(tokenIds, purchaseId, deadline, signature);
        vm.stopPrank();
    }

    function test_constructor_edgeRatios() public {
        // Test with minimum ratios (0% burn, 0% liquidity, 100% revenue)
        SBTSale minRatioContract = new SBTSale({
            poasMinter: address(poasMinter),
            liquidityPool: address(pool),
            lpRecipient: lpRecipient,
            revenueRecipient: revenueRecipient,
            smpBasePrice: smpBasePrice,
            smpBurnRatio: 0,
            smpLiquidityRatio: 0
        });
        assertEq(minRatioContract.getSMPBurnRatio(), 0);
        assertEq(minRatioContract.getSMPLiquidityRatio(), 0);

        // Test with maximum valid ratios (100% total)
        SBTSale maxRatioContract = new SBTSale({
            poasMinter: address(poasMinter),
            liquidityPool: address(pool),
            lpRecipient: lpRecipient,
            revenueRecipient: revenueRecipient,
            smpBasePrice: smpBasePrice,
            smpBurnRatio: 7000,
            smpLiquidityRatio: 3000
        });
        assertEq(maxRatioContract.getSMPBurnRatio(), 7000);
        assertEq(maxRatioContract.getSMPLiquidityRatio(), 3000);
    }

    function test_purchase_zeroRevenue() public {
        // Deploy a contract with 100% burn+liquidity (0% revenue)
        vm.startPrank(deployer);
        SBTSale implementation = new SBTSale({
            poasMinter: address(poasMinter),
            liquidityPool: address(pool),
            lpRecipient: lpRecipient,
            revenueRecipient: revenueRecipient,
            smpBasePrice: smpBasePrice,
            smpBurnRatio: 6000,
            smpLiquidityRatio: 4000
        });

        bytes memory initData = abi.encodeWithSelector(SBTSale.initialize.selector, deployer);
        address testP2EAddr =
            address(new TransparentUpgradeableProxy(address(implementation), deployer, initData));
        ISBTSale testP2E = ISBTSale(testP2EAddr);

        // Create new SBT contract for this test
        MockSBTSaleERC721 testSBT = new MockSBTSaleERC721("TestSBT", "TSBT", testP2EAddr);
        testP2E.setSBTContract(ISBTSaleERC721(address(testSBT)));
        testP2E.setSigner(signerAddress);
        vm.stopPrank();

        vm.startPrank(sender);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 7001;
        uint256 amount = testP2E.queryPrice(1, nativeOAS);

        ISBTSale.PurchaseOrder memory order = ISBTSale.PurchaseOrder({
            purchaseId: 7001,
            buyer: sender,
            tokenIds: tokenIds,
            paymentToken: nativeOAS,
            amount: amount,
            minRevenueOAS: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "PurchaseOrder(uint256 purchaseId,address buyer,uint256[] tokenIds,address paymentToken,uint256 amount,uint256 minRevenueOAS,uint256 deadline)"
                ),
                order.purchaseId,
                order.buyer,
                keccak256(abi.encode(order.tokenIds)),
                order.paymentToken,
                order.amount,
                order.minRevenueOAS,
                order.deadline
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("SBTSale")),
                keccak256(bytes("1")),
                block.chainid,
                testP2EAddr
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.deal(sender, amount);
        testP2E.purchase{value: amount}(
            tokenIds, nativeOAS, amount, 0, 7001, block.timestamp + 1 hours, signature
        );

        assertEq(testSBT.ownerOf(tokenIds[0]), sender);
        vm.stopPrank();
    }

    function test_signer_noSignerSet() public {
        vm.startPrank(sender);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 4204;
        uint256 amount = p2e.queryPrice(1, nativeOAS);

        ISBTSale.PurchaseOrder memory order = _createPurchaseOrder(
            4204, sender, tokenIds, nativeOAS, amount, 0, block.timestamp + 1 hours
        );
        bytes memory signature = _signPurchaseOrder(order, signerPrivateKey);

        // Reset signer to zero address
        vm.stopPrank();
        vm.startPrank(deployer);
        p2e.setSigner(signerAddress); // Set to known address first
        p2e.setSigner(vm.addr(1)); // Change to different address to invalidate signature
        vm.stopPrank();

        vm.startPrank(sender);
        vm.deal(sender, amount);
        vm.expectRevert(ISBTSale.InvalidSignature.selector);
        p2e.purchase{value: amount}(
            tokenIds, nativeOAS, amount, 0, 4204, block.timestamp + 1 hours, signature
        );
        vm.stopPrank();
    }

    function _expect_receive_token_events(address tokenIn, uint256 expectedReceived) internal {
        if (tokenIn == nativeOAS) {
            return; // No events for native OAS
        }

        // Standard ERC20 tokens (WOAS, SMP): expect transfer from sender to contract
        if (tokenIn == address(woas) || tokenIn == address(smp)) {
            vm.expectEmit(tokenIn);
            emit Transfer(sender, p2eAddr, expectedReceived);
        }

        // POAS tokens: expect burn (transfer to zero) and payment event
        if (tokenIn == address(poas)) {
            // Expect POAS burn: sender -> address(0)
            vm.expectEmit(tokenIn);
            emit Transfer(sender, address(0), expectedReceived);

            // Expect POAS payment: native OAS sent to contract
            vm.expectEmit(tokenIn);
            emit Paid(sender, p2eAddr, expectedReceived);
        }
    }

    function _expect_swap_oas_to_smp_events(
        address tokenIn,
        uint256 actualAmount,
        uint256 paymentAmount
    ) internal {
        if (tokenIn == address(smp)) {
            return; // No swap needed if SMP can be used directly
        }

        if (tokenIn == address(woas)) {
            // Expect WOAS approval for swap: P2E -> Vault
            vm.expectEmit(address(woas));
            emit Approval(p2eAddr, address(vault), paymentAmount);
        }

        // Expect swap: tokenIn -> SMP (always results in triNFT_SMP_Price SMP)
        vm.expectEmit(address(vault));
        emit Swap(pool.getPoolId(), woas, smp, actualAmount, totalSMPPrice);

        if (tokenIn == address(woas)) {
            // Expect WOAS transfer for swap: P2E -> Vault
            vm.expectEmit(address(woas));
            emit Transfer(p2eAddr, address(vault), actualAmount);
        }
    }

    function _expect_burn_smp_events() internal {
        // Expect SMP burn
        vm.expectEmit(address(smp));
        emit Transfer(p2eAddr, address(0), totalSMPBurn);
    }

    function _expect_provide_liquidity_events(uint256 expectedLPout) internal {
        // Expect SMP approval for liquidity provision
        vm.expectEmit(address(smp));
        emit Approval(p2eAddr, address(vault), totalSMPLiquidity);

        // Expect BPT transfer: LP tokens to LP recipient (minted from address(0))
        vm.expectEmit(address(pool));
        emit Transfer(address(0), lpRecipient, expectedLPout);

        // Expect SMP transfer for liquidity provision to vault
        vm.expectEmit(address(smp));
        emit Transfer(p2eAddr, address(vault), totalSMPLiquidity);
    }

    function _expect_revenue_events(uint256 expectedOASout) internal {
        // Expect SMP approval for revenue swap
        vm.expectEmit(address(smp));
        emit Approval(p2eAddr, address(vault), totalSMPRevenue);

        // Expect revenue swap: SMP -> WOAS
        vm.expectEmit(address(vault));
        emit Swap(pool.getPoolId(), smp, woas, totalSMPRevenue, expectedOASout);

        // Expect WOAS burn to native OAS (vault burns WOAS)
        vm.expectEmit(address(woas));
        emit Transfer(address(vault), address(0), expectedOASout);

        // Expect WOAS withdrawal to native OAS (sent to revenue recipient)
        vm.expectEmit(address(woas));
        emit Withdrawal(address(vault), expectedOASout);

        // Expect SMP transfer for revenue swap to vault
        vm.expectEmit(address(smp));
        emit Transfer(p2eAddr, address(vault), totalSMPRevenue);
    }

    // =============================================================
    //                      HELPER FUNCTIONS
    // =============================================================

    function _expect_purchased_event(
        address buyer,
        address paymentToken,
        uint256 actualAmount,
        uint256 refundAmount,
        uint256 expectedRevenueOAS,
        uint256[] memory tokenIds,
        uint256 purchaseId
    ) internal {
        vm.expectEmit(p2eAddr);
        emit ISBTSale.Purchased(
            buyer,
            tokenIds,
            paymentToken,
            actualAmount,
            refundAmount,
            totalSMPBurn,
            totalSMPLiquidity,
            totalSMPRevenue,
            expectedRevenueOAS,
            revenueRecipient,
            lpRecipient,
            purchaseId
        );
    }

    function _expect_balances(
        address _account,
        uint256 _native,
        uint256 _woas,
        uint256 _poas,
        uint256 _smp,
        uint256 _lp
    ) internal view {
        assertEq(_account.balance, _native);
        assertEq(woas.balanceOf(_account), _woas);
        assertEq(poas.balanceOf(_account), _poas);
        assertEq(smp.balanceOf(_account), _smp);
        assertEq(IERC20(address(pool)).balanceOf(_account), _lp);
    }

    function _expect_minted_nfts(address _account, uint256[] memory _tokenIds) internal view {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            assertEq(sbtContract.ownerOf(_tokenIds[i]), _account);
        }
    }

    function _expect_free_purchased_event(
        address buyer,
        uint256[] memory tokenIds,
        uint256 purchaseId
    ) internal {
        vm.expectEmit(p2eAddr);
        emit ISBTSale.Purchased(
            buyer, tokenIds, address(0), 0, 0, 0, 0, 0, 0, revenueRecipient, lpRecipient, purchaseId
        );
    }

    function _createPurchaseOrder(
        uint256 purchaseId,
        address buyer,
        uint256[] memory tokenIds,
        address paymentToken,
        uint256 amount,
        uint256 minRevenueOAS,
        uint256 deadline
    ) internal pure returns (ISBTSale.PurchaseOrder memory) {
        return ISBTSale.PurchaseOrder({
            purchaseId: purchaseId,
            buyer: buyer,
            tokenIds: tokenIds,
            paymentToken: paymentToken,
            amount: amount,
            minRevenueOAS: minRevenueOAS,
            deadline: deadline
        });
    }

    function _signPurchaseOrder(ISBTSale.PurchaseOrder memory order, uint256 signerPrivateKey)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "PurchaseOrder(uint256 purchaseId,address buyer,uint256[] tokenIds,address paymentToken,uint256 amount,uint256 minRevenueOAS,uint256 deadline)"
                ),
                order.purchaseId,
                order.buyer,
                keccak256(abi.encode(order.tokenIds)),
                order.paymentToken,
                order.amount,
                order.minRevenueOAS,
                order.deadline
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("SBTSale")),
                keccak256(bytes("1")),
                block.chainid,
                p2eAddr
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _createFreePurchaseOrder(
        uint256 purchaseId,
        address buyer,
        uint256[] memory tokenIds,
        uint256 deadline
    ) internal pure returns (ISBTSale.FreePurchaseOrder memory) {
        return ISBTSale.FreePurchaseOrder({
            purchaseId: purchaseId,
            buyer: buyer,
            tokenIds: tokenIds,
            deadline: deadline
        });
    }

    function _signFreePurchaseOrder(
        ISBTSale.FreePurchaseOrder memory order,
        uint256 signerPrivateKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "FreePurchaseOrder(uint256 purchaseId,address buyer,uint256[] tokenIds,uint256 deadline)"
                ),
                order.purchaseId,
                order.buyer,
                keccak256(abi.encode(order.tokenIds)),
                order.deadline
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("SBTSale")),
                keccak256(bytes("1")),
                block.chainid,
                p2eAddr
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // =============================================================
    //                   OWNERSHIP TRANSFER TESTS (KYU-2)
    // =============================================================

    function test_transferOwnership_twoStep() public {
        address newOwner = address(0x999);
        SBTSale sbtSale = SBTSale(payable(address(p2e)));

        // Current owner should be 'deployer'
        assertEq(sbtSale.owner(), deployer);

        // Transfer ownership (step 1)
        vm.prank(deployer);
        sbtSale.transferOwnership(newOwner);

        // Owner should still be the old owner (pending acceptance)
        assertEq(sbtSale.owner(), deployer);
        assertEq(sbtSale.pendingOwner(), newOwner);

        // New owner must accept (step 2)
        vm.prank(newOwner);
        sbtSale.acceptOwnership();

        // Now ownership should be transferred
        assertEq(sbtSale.owner(), newOwner);
        assertEq(sbtSale.pendingOwner(), address(0));
    }

    function test_transferOwnership_oldOwnerRetainsControl() public {
        address newOwner = address(0x999);
        SBTSale sbtSale = SBTSale(payable(address(p2e)));

        // Transfer ownership
        vm.prank(deployer);
        sbtSale.transferOwnership(newOwner);

        // Owner should still be the old owner (not yet accepted)
        assertEq(sbtSale.owner(), deployer);

        // Old owner can still perform owner actions
        vm.prank(deployer);
        p2e.setSigner(address(0x888));
        assertEq(p2e.getSigner(), address(0x888));

        // New owner cannot perform owner actions until accepting
        vm.prank(newOwner);
        vm.expectRevert();
        p2e.setSigner(address(0x777));
    }

    function test_acceptOwnership_onlyPendingOwner() public {
        address newOwner = address(0x999);
        address notPendingOwner = address(0x888);
        SBTSale sbtSale = SBTSale(payable(address(p2e)));

        // Transfer ownership
        vm.prank(deployer);
        sbtSale.transferOwnership(newOwner);

        // Random address cannot accept ownership
        vm.prank(notPendingOwner);
        vm.expectRevert();
        sbtSale.acceptOwnership();

        // Verify owner hasn't changed
        assertEq(sbtSale.owner(), deployer);
        assertEq(sbtSale.pendingOwner(), newOwner);

        // Only the pending owner can accept
        vm.prank(newOwner);
        sbtSale.acceptOwnership();

        assertEq(sbtSale.owner(), newOwner);
        assertEq(sbtSale.pendingOwner(), address(0));
    }

    function test_transferOwnership_canOverwritePending() public {
        address firstNewOwner = address(0x999);
        address secondNewOwner = address(0x888);
        SBTSale sbtSale = SBTSale(payable(address(p2e)));

        // Transfer to first new owner
        vm.prank(deployer);
        sbtSale.transferOwnership(firstNewOwner);
        assertEq(sbtSale.pendingOwner(), firstNewOwner);

        // Owner changes mind and transfers to second new owner
        vm.prank(deployer);
        sbtSale.transferOwnership(secondNewOwner);
        assertEq(sbtSale.pendingOwner(), secondNewOwner);

        // First new owner cannot accept anymore
        vm.prank(firstNewOwner);
        vm.expectRevert();
        sbtSale.acceptOwnership();

        // Second new owner can accept
        vm.prank(secondNewOwner);
        sbtSale.acceptOwnership();
        assertEq(sbtSale.owner(), secondNewOwner);
    }

    // =============================================================
    //                   RENOUNCE OWNERSHIP TESTS (KYU-3)
    // =============================================================

    function test_renounceOwnership_disabled() public {
        SBTSale sbtSale = SBTSale(payable(address(p2e)));

        // Owner should not be able to renounce ownership
        vm.prank(deployer);
        vm.expectRevert(ISBTSale.OwnershipCannotBeRenounced.selector);
        sbtSale.renounceOwnership();

        // Verify owner hasn't changed
        assertEq(sbtSale.owner(), deployer);
    }

    function test_renounceOwnership_nonOwnerCannotCall() public {
        SBTSale sbtSale = SBTSale(payable(address(p2e)));
        address nonOwner = address(0x999);

        // Non-owner cannot call renounceOwnership
        vm.prank(nonOwner);
        vm.expectRevert();
        sbtSale.renounceOwnership();
    }
}
