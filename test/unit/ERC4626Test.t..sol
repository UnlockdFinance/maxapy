// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import {BaseTest, IERC20, Vm, console} from "../base/BaseTest.t.sol";
import {IStrategyWrapper} from "../interfaces/IStrategyWrapper.sol";
import {IMaxApyVaultV2} from "src/interfaces/IMaxApyVaultV2.sol";
import {MaxApyVaultV2} from "src/MaxApyVaultV2.sol";
import {StrategyData} from "src/helpers/VaultTypes.sol";
import {StrategyEvents} from "../helpers/StrategyEvents.sol";
import {ICurve} from "src/interfaces/ICurve.sol";
import {IUniswapV2Router02 as IRouter} from "src/interfaces/IUniswap.sol";
import {ConvexPools} from "../helpers/ConvexPools.sol";

import {ConvexdETHFrxETHStrategyWrapper} from "../mock/ConvexdETHFrxETHStrategyWrapper.sol";
import {ConvexdETHFrxETHStrategyEvents} from "../helpers/ConvexdETHFrxETHStrategyEvents.sol";

import {SommelierMorphoEthMaximizerStrategyWrapper} from "../mock/SommelierMorphoEthMaximizerStrategyWrapper.sol";
import {SommelierMorphoEthMaximizerStrategy} from
    "src/strategies/WETH/sommelier/SommelierMorphoEthMaximizerStrategy.sol";

import {SommelierTurboStEthStrategy} from "src/strategies/WETH/sommelier/SommelierTurboStEthStrategy.sol";
import {SommelierTurboStEthStrategyWrapper} from "../mock/SommelierTurboStEthStrategyWrapper.sol";

import {SommelierStEthDepositTurboStEthStrategyWrapper} from
    "../mock/SommelierStEthDepositTurboStEthStrategyWrapper.sol";

import {YearnWETHStrategyWrapper} from "../mock/YearnWETHStrategyWrapper.sol";

contract ERC4626Test is BaseTest, StrategyEvents, ConvexPools {
    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////
    address public constant CELLAR_WETH_MAINNET_MORPHO = 0xcf4B531b4Cde95BD35d71926e09B2b54c564F5b6;
    address public constant CELLAR_WETH_MAINNET_STETH = 0xfd6db5011b171B05E1Ea3b92f9EAcaEEb055e971;
    address public constant CELLAR_STETH_MAINNET = 0xc7372Ab5dd315606dB799246E8aA112405abAeFf;
    address public constant YVAULT_WETH_MAINNET = 0xa258C4606Ca8206D8aA700cE2143D7db854D168c;

    address public constant CURVE_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    IERC20 public constant crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public constant cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public constant frxEth = IERC20(0x5E8422345238F34275888049021821E8E08CAa1f);

    IRouter public constant SUSHISWAP_ROUTER = IRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    address public TREASURY;

    ////////////////////////////////////////////////////////////////
    ///                      HELPER FUNCTION                     ///
    ////////////////////////////////////////////////////////////////
    function _dealStEth(address give, uint256 wethIn) internal returns (uint256 stEthOut) {
        vm.deal(give, wethIn);
        stEthOut = ICurve(CURVE_POOL).exchange{value: wethIn}(0, 1, wethIn, 0);
        IERC20(ST_ETH).transfer(give, stEthOut >= wethIn ? wethIn : stEthOut);
    }

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy1; // yearn
    IStrategyWrapper public strategy2; // sommelier turbo steth
    IStrategyWrapper public strategy3; // sommelier steth deposit
    IStrategyWrapper public strategy4; // convex

    IMaxApyVaultV2 public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function setUp() public override {
        super.setUp();

        TREASURY = makeAddr("treasury");

        /// Deploy MaxApyVaultV2
        MaxApyVaultV2 vaultDeployment = new MaxApyVaultV2(WETH, "MaxApyWETHVault", "maxApy", TREASURY);

        vault = IMaxApyVaultV2(address(vaultDeployment));
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        // Deploy strategy1
        YearnWETHStrategyWrapper implementation1 = new YearnWETHStrategyWrapper();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                users.alice,
                YVAULT_WETH_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(YVAULT_WETH_MAINNET, "yVault");
        vm.label(address(proxy), "YearnWETHStrategy");
        strategy1 = IStrategyWrapper(address(_proxy));

        // Deploy strategy2
        SommelierTurboStEthStrategyWrapper implementation2 = new SommelierTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation2),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                users.alice,
                CELLAR_WETH_MAINNET_STETH
            )
        );
        vm.label(CELLAR_WETH_MAINNET_STETH, "Cellar");
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierTurbStEthStrategy");

        strategy2 = IStrategyWrapper(address(_proxy));

        // Deploy strategy3
        SommelierStEthDepositTurboStEthStrategyWrapper implementation3 =
            new SommelierStEthDepositTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation3),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                users.alice,
                CELLAR_STETH_MAINNET,
                CURVE_POOL
            )
        );
        vm.label(CELLAR_STETH_MAINNET, "Cellar");
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierStEThDeposiTurbStEthStrategy");
        vm.label(ST_ETH, "StETH");

        strategy3 = IStrategyWrapper(address(_proxy));

        // Deploy strategy4
        ConvexdETHFrxETHStrategyWrapper implementation4 = new ConvexdETHFrxETHStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation4),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address)",
                address(vault),
                keepers,
                users.alice,
                bytes32(abi.encode("MaxApy dETH<>frxETH Strategy")),
                DETH_FRXETH_CURVE_POOL,
                ETH_FRXETH_CURVE_POOL,
                address(SUSHISWAP_ROUTER)
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "ConvexdETHFrxETHStrategy");

        strategy4 = IStrategyWrapper(address(_proxy));

        // Add all the strategies
        vault.addStrategy(address(strategy1), 2250, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy2), 2250, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy3), 2250, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy4), 2250, type(uint72).max, 0, 0);

        vm.rollFork(19267583);
        vm.label(address(WETH), "WETH");
        /// Alice approves vault for deposits
        IERC20(WETH).approve(address(vault), type(uint256).max);
        vm.startPrank(users.bob);
        IERC20(WETH).approve(address(vault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(users.alice);
    }

    function testMaxApyVaultV2_ERC4626__PreviewDeposit() public {
        /// 1.deposit when the vault is empty
        uint256 expectedShares = vault.previewDeposit(20 ether);
        uint256 sharesReturn = vault.deposit(20 ether, users.alice);
        assertEq(sharesReturn, expectedShares);
        assertEq(vault.balanceOf(users.alice), expectedShares);
        assertEq(IERC20(WETH).balanceOf(address(vault)), 20 ether);

        /// 2. deposit when the vault has funds
        expectedShares = vault.previewDeposit(20 ether);
        sharesReturn = vault.deposit(20 ether, users.alice);
        assertEq(sharesReturn, expectedShares);
        assertEq(vault.balanceOf(users.alice), expectedShares * 2);
        assertEq(IERC20(WETH).balanceOf(address(vault)), 40 ether);
    }

    function testMaxApyVaultV2_ERC4626__PreviewMint() public {
        /// 1.mint when the vault is empty
        uint256 expectedAssets = vault.previewMint(20 ether);
        uint256 assetsReturn = vault.mint(20 ether, users.alice);
        assertEq(assetsReturn, expectedAssets);
        assertEq(vault.balanceOf(users.alice), 20 ether);
        assertEq(IERC20(WETH).balanceOf(address(vault)), expectedAssets);

        /// 2. mint when the vault has funds
        expectedAssets = vault.previewMint(20 ether);
        assetsReturn = vault.mint(20 ether, users.alice);
        assertEq(assetsReturn, expectedAssets);
        assertEq(vault.balanceOf(users.alice), 40 ether);
        assertEq(IERC20(WETH).balanceOf(address(vault)), expectedAssets * 2);
    }

    function testMaxApyVaultV2_ERC4626__PreviewRedeem() public {
        /// ⭕️ SCENARIO 1: Redeem when all the funds are in the vault
        /// - Alice deposits 20 WETH
        /// - Bob deposits 500 WETH
        /// - Alice and Bob redeem
        uint256 sharesAlice = vault.deposit(20 ether, users.alice);
        // other uses deposits as well
        deal(WETH, users.bob, 500 ether);
        vm.startPrank(users.bob);
        uint256 sharesBob = vault.deposit(500 ether, users.bob);
        vm.stopPrank();
        vm.startPrank(users.alice);

        uint256 snapshotId = vm.snapshot();
        assertEq(vault.redeem(type(uint256).max, users.alice, users.alice), vault.previewRedeem(sharesAlice));
        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 2: Redeem when some funds are in strategies
        /// - Alice deposits 20 WETH
        /// - Bob deposits 500 WETH
        /// - Harvest strategies so they take the vault money
        /// - Alice and Bob redeem
        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, 0);
        strategy2.harvest(0, 0, 0);
        strategy3.harvest(0, 0, 0);
        strategy4.harvest(0, 0, 0);
        vm.stopPrank();
        vm.startPrank(users.alice);
        uint256 expectedAssets = vault.previewRedeem(sharesAlice);
        uint256 assets = vault.redeem(type(uint256).max, users.alice, users.alice);
        assertEq(assets, expectedAssets);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedAssets = vault.previewRedeem(sharesBob);
        assets = vault.redeem(type(uint256).max, users.bob, users.bob);
        assertEq(assets, expectedAssets);
        vm.stopPrank();
        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3: Redeem when some funds are in strategies and they have profits
        /// - Alice deposits 20 WETH
        /// - Bob deposits 500 WETH
        /// - Harvest strategies so they take the vault money
        /// - Strategies make profit
        /// - Harvest again
        /// - Alice and Bob redeem
        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, 0);
        strategy2.harvest(0, 0, 0);
        strategy3.harvest(0, 0, 0);
        strategy4.harvest(0, 0, 0);
        deal(WETH, address(strategy1), 50 ether);
        // forward time so lastReport timestamp is not the same
        skip(1);
        strategy1.harvest(0, 0, 0);
        vm.stopPrank();
        vm.startPrank(users.alice);
        expectedAssets = vault.previewRedeem(sharesAlice);
        assets = vault.redeem(type(uint256).max, users.alice, users.alice);
        assertEq(assets, expectedAssets);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedAssets = vault.previewRedeem(sharesBob);
        assets = vault.redeem(type(uint256).max, users.bob, users.bob);
        assertEq(assets, expectedAssets);
        vm.stopPrank();
        vm.revertTo(snapshotId);
    }

    function testMaxApyVaultV2_ERC4626__PreviewWithdraw() public {
        /// ⭕️ SCENARIO 1: withdraw when all the funds are in the vault
        /// - Alice deposits 20 WETH
        /// - Bob deposits 5,000 WETH
        /// - Alice and Bob withdraw
        vault.deposit(20 ether, users.alice);
        // other users deposits as well
        deal(WETH, users.bob, 500 ether);

        vm.startPrank(users.bob);
        IERC20(WETH).approve(address(vault), type(uint256).max);
        vault.deposit(500 ether, users.bob);
        vm.stopPrank();

        vm.startPrank(users.alice);
        uint256 snapshotId = vm.snapshot();
        uint256 expectedShares = vault.previewWithdraw(20 ether);
        uint256 balanceBefore = IERC20(WETH).balanceOf(users.alice);
        uint256 shares = vault.withdraw(20 ether, users.alice, users.alice);
        uint256 transferred = IERC20(WETH).balanceOf(users.alice) - balanceBefore;
        assertEq(transferred, 20 ether);
        assertLe(shares, expectedShares);

        vm.startPrank(users.bob);
        expectedShares = vault.previewWithdraw(400 ether);
        balanceBefore = IERC20(WETH).balanceOf(users.bob);
        shares = vault.withdraw(400 ether, users.bob, users.bob);
        transferred = IERC20(WETH).balanceOf(users.bob) - balanceBefore;
        assertEq(transferred, 400 ether);
        assertLe(shares, expectedShares);
        vm.stopPrank();

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 2: withdraw when some funds are in strategies
        /// - Alice deposits 18 WETH
        /// - Bob deposits 400 WETH
        /// - Harvest strategies so they take the vault money
        /// - Alice and Bob withdraw
        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, 0);
        strategy2.harvest(0, 0, 0);
        strategy3.harvest(0, 0, 0);
        strategy4.harvest(0, 0, 0);
        vm.stopPrank();
        vm.startPrank(users.alice);
        expectedShares = vault.previewWithdraw(18 ether);
        balanceBefore = IERC20(WETH).balanceOf(users.alice);
        shares = vault.withdraw(18 ether, users.alice, users.alice);
        transferred = IERC20(WETH).balanceOf(users.alice) - balanceBefore;
        assertEq(transferred, 18 ether);
        assertLe(shares, expectedShares);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedShares = vault.previewWithdraw(400 ether);
        balanceBefore = IERC20(WETH).balanceOf(users.bob);
        shares = vault.withdraw(400 ether, users.bob, users.bob);
        transferred = IERC20(WETH).balanceOf(users.bob) - balanceBefore;
        assertEq(transferred, 400 ether);
        assertLe(shares, expectedShares);
        vm.stopPrank();
        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3: withdraw when some funds are in strategies and they have profits
        /// - Alice deposits 19 WETH
        /// - Bob deposits 400 WETH
        /// - Harvest strategies so they take the vault money
        /// - Strategies make profit
        /// - Harvest again
        /// - Alice and Bob withdraw
        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, 0);
        strategy2.harvest(0, 0, 0);
        strategy3.harvest(0, 0, 0);
        strategy4.harvest(0, 0, 0);
        vm.stopPrank();
        vm.startPrank(users.alice);
        expectedShares = vault.previewWithdraw(19 ether);
        balanceBefore = IERC20(WETH).balanceOf(users.alice);
        shares = vault.withdraw(19 ether, users.alice, users.alice);
        transferred = IERC20(WETH).balanceOf(users.alice) - balanceBefore;
        assertEq(transferred, 19 ether);
        assertLe(shares, expectedShares);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedShares = vault.previewWithdraw(400 ether);
        balanceBefore = IERC20(WETH).balanceOf(users.bob);
        shares = vault.withdraw(400 ether, users.bob, users.bob);
        transferred = IERC20(WETH).balanceOf(users.bob) - balanceBefore;
        assertEq(transferred, 400 ether);
        assertLe(shares, expectedShares);
        vm.stopPrank();
        vm.revertTo(snapshotId);
    }

    function testMaxApyVaultV2_ERC4626__PreviewWithdraw_FUZZY(uint256 amount) public {
        vm.assume(amount > 1 ether / 10 && amount < 10_000 ether);
        vault.deposit(20 ether, users.alice);
        // other users deposits as well
        vm.startPrank(users.bob);
        deal(WETH, users.bob, amount * 2);
        IERC20(WETH).approve(address(vault), type(uint256).max);
        vault.deposit(amount * 2, users.bob);
        vm.stopPrank();

        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, 0);
        strategy2.harvest(0, 0, 0);
        strategy3.harvest(0, 0, 0);
        strategy4.harvest(0, 0, 0);
        deal(WETH, address(strategy1), 50 ether);
        vm.stopPrank();

        vm.startPrank(users.alice);
        uint256 expectedShares = vault.previewWithdraw(19 ether);
        uint256 balanceBefore = IERC20(WETH).balanceOf(users.alice);
        uint256 shares = vault.withdraw(19 ether, users.alice, users.alice);
        uint256 transferred = IERC20(WETH).balanceOf(users.alice) - balanceBefore;
        assertEq(transferred, 19 ether);
        assertLe(shares, expectedShares);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedShares = vault.previewWithdraw(amount);
        balanceBefore = IERC20(WETH).balanceOf(users.bob);
        shares = vault.withdraw(amount, users.bob, users.bob);
        transferred = IERC20(WETH).balanceOf(users.bob) - balanceBefore;
        assertEq(transferred, amount);
        assertLe(shares, expectedShares);
        vm.stopPrank();
    }

    function testMaxApyVaultV2_ERC4626__sharePrice() external {
        vault.deposit(20 ether, users.alice);
        assertEq(vault.sharePrice(), 1 ether);

        assertEq(strategy1.estimatedTotalAssets(), 0);
        assertEq(strategy1.lastEstimatedTotalAssets(), 0);

        // sending assets directly to the vault won't work
        deal(WETH, address(vault), 500 ether);
        assertEq(vault.sharePrice(), 1 ether);

        // share price might slightly decrease after investing
        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, 0);
        strategy2.harvest(0, 0, 0);
        strategy3.harvest(0, 0, 0);
        strategy4.harvest(0, 0, 0);
        assertApproxEq(vault.sharePrice(), 1 ether, 1 ether / 1000);

        // sending assets directly to the strategy won't work
        deal(WETH, address(strategy1), 5 ether);
        assertApproxEq(vault.sharePrice(), 1 ether, 1 ether / 1000);
        skip(1);
        strategy1.harvest(0, 0, 0);
      
        assertApproxEq(vault.sharePrice(), 1 ether * 125 / 100, 1 ether);

        // if the strategy has losses it should instantly be reflected in the share price
        vm.stopPrank();
        vm.startPrank(address(strategy1));
        // transfer shares to a random addresss
        IERC20(YVAULT_WETH_MAINNET).transfer(makeAddr("random"), strategy1.sharesForAmount(5 ether));

        // the share price gets back to the initial value approx
        assertApproxEq(vault.sharePrice(), 1 ether, 0.03 ether);
    }
}
