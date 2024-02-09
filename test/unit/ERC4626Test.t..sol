// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import {BaseTest, IERC20, Vm, console} from "../base/BaseTest.t.sol";
import {IStrategyWrapper} from "../interfaces/IStrategyWrapper.sol";
import {IMaxApyVaultV2} from "../../src/interfaces/IMaxApyVaultV2.sol";
import {SommelierTurboGHOStrategyWrapper} from "../mock/SommelierTurboGHOStrategyWrapper.sol";
import {SommelierRealYieldStrategyWrapper} from "../mock/SommelierRealYieldStrategyWrapper.sol";
import {MaxApyVaultV2} from "../../src/MaxApyVaultV2.sol";
import {StrategyData} from "../../src/helpers/VaultTypes.sol";
import {SommelierTurboGHOStrategy} from "../../src/strategies/sommelier/SommelierTurboGHOStrategy.sol";
import {YearnStrategyEvents} from "../helpers/YearnStrategyEvents.sol";

contract ERC4626Test is BaseTest, YearnStrategyEvents {
    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////
    address public constant TURBO_GHO_CELLAR = 0x0C190DEd9Be5f512Bd72827bdaD4003e9Cc7975C;
    address public constant REAL_YIELD_USD_CELLAR = 0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E;
    address public TREASURY;
    uint256 public _1_USDC = 1e6;

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy0;
    IStrategyWrapper public strategy1;
    SommelierTurboGHOStrategyWrapper public implementation0;
    SommelierRealYieldStrategyWrapper public implementation1;
    MaxApyVaultV2 public vaultDeployment;
    IMaxApyVaultV2 public vault;
    ITransparentUpgradeableProxy public proxy0;
    ITransparentUpgradeableProxy public proxy1;
    ProxyAdmin public proxyAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function setUp() public override {
        super.setUp();

        TREASURY = makeAddr("treasury");

        /// Deploy MaxApyVaultV2
        vaultDeployment = new MaxApyVaultV2(USDC, "MaxApyUSDCVault", "maxApy", TREASURY);

        vault = IMaxApyVaultV2(address(vaultDeployment));
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin();
        /// Deploy strategy implementation
        implementation0 = new SommelierTurboGHOStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        /// Deploy transparent upgradeable proxy
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation0),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Turbo GHO Strategy")),
                users.alice,
                TURBO_GHO_CELLAR
            )
        );
        vm.label(TURBO_GHO_CELLAR, "SommelierTurboGHOStrategy Cellar");
        proxy0 = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy0), "SommelierTurboGHOStrategy");
        vm.label(address(USDC), "USDC");

        strategy0 = IStrategyWrapper(address(_proxy));

        /// Deploy strategy implementation
        implementation1 = new SommelierRealYieldStrategyWrapper();

        /// Deploy transparent upgradeable proxy
        _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Real USD Strategy")),
                users.alice,
                REAL_YIELD_USD_CELLAR
            )
        );
        vm.label(REAL_YIELD_USD_CELLAR, "SommelierRealYieldUSDStrategy Cellar");
        proxy1 = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy1), "SommelierRealYieldUSDStrategy");

        strategy1 = IStrategyWrapper(address(_proxy));

        /// Alice approves vault for deposits
        IERC20(USDC).approve(address(vault), 0);
        IERC20(USDC).approve(address(vault), type(uint256).max);

        vm.rollFork(18609089);
    }

    function testMaxApyVaultV2_ERC4626__PreviewDeposit() public {
        /// 1.deposit when the vault is empty
        uint256 expectedShares = vault.previewDeposit(200 * _1_USDC);
        uint256 sharesReturn = vault.deposit(200 * _1_USDC, users.alice);
        assertEq(sharesReturn, expectedShares);
        assertEq(vault.balanceOf(users.alice), expectedShares);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 200 * _1_USDC);

        /// 2. deposit when the vault has funds
        expectedShares = vault.previewDeposit(200 * _1_USDC);
        sharesReturn = vault.deposit(200 * _1_USDC, users.alice);
        assertEq(sharesReturn, expectedShares);
        assertEq(vault.balanceOf(users.alice), expectedShares * 2);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 400 * _1_USDC);
    }

    function testMaxApyVaultV2_ERC4626__PreviewMint() public {
        /// 1.mint when the vault is empty
        uint256 expectedAssets = vault.previewMint(200 * _1_USDC);
        uint256 assetsReturn = vault.mint(200 * _1_USDC, users.alice);
        assertEq(assetsReturn, expectedAssets);
        assertEq(vault.balanceOf(users.alice), 200 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(vault)), expectedAssets);

        /// 2. mint when the vault has funds
        expectedAssets = vault.previewMint(200 * _1_USDC);
        assetsReturn = vault.mint(200 * _1_USDC, users.alice);
        assertEq(assetsReturn, expectedAssets);
        assertEq(vault.balanceOf(users.alice), 400 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(vault)), expectedAssets * 2);
    }

    function testMaxApyVaultV2_ERC4626__PreviewRedeem() public {
        vault.addStrategy(address(strategy0), 4000, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy1), 5000, type(uint72).max, 0, 0);

        /// ⭕️ SCENARIO 1: Redeem when all the funds are in the vault
        /// - Alice deposits 200 USDC
        /// - Bob deposits 5000 USDC
        /// - Alice and Bob redeem
        uint256 sharesAlice = vault.deposit(200 * _1_USDC, users.alice);
        // other uses deposits as well
        deal(USDC, users.bob, 5000 * _1_USDC);
        vm.startPrank(users.bob);
        IERC20(USDC).approve(address(vault), type(uint256).max);
        uint256 sharesBob = vault.deposit(5000 * _1_USDC, users.bob);
        vm.stopPrank();
        vm.startPrank(users.alice);

        uint256 snapshotId = vm.snapshot();
        assertEq(vault.redeem(sharesAlice, users.alice, users.alice), vault.previewRedeem(sharesAlice));
        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 2: Redeem when some funds are in strategies
        /// - Alice deposits 200 USDC
        /// - Bob deposits 5000 USDC
        /// - Harvest strategies so they take the vault money
        /// - Alice and Bob redeem
        vm.startPrank(users.keeper);
        strategy0.harvest(0, 0);
        vm.stopPrank();
        vm.startPrank(users.alice);
        uint256 expectedAssets = vault.previewRedeem(sharesAlice);
        uint256 assets = vault.redeem(sharesAlice, users.alice, users.alice);
        assertEq(assets, expectedAssets);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedAssets = vault.previewRedeem(sharesBob);
        assets = vault.redeem(sharesBob, users.bob, users.bob);
        assertEq(assets, expectedAssets);
        vm.stopPrank();
        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3: Redeem when some funds are in strategies and they have profits
        /// - Alice deposits 200 USDC
        /// - Bob deposits 5000 USDC
        /// - Harvest strategies so they take the vault money
        /// - Strategies make profit
        /// - Harvest again
        /// - Alice and Bob redeem
        vm.startPrank(users.keeper);
        strategy0.harvest(0, 0);
        deal(USDC, address(strategy0), 50 * _1_USDC);
        strategy0.harvest(0, 0);
        vm.stopPrank();
        vm.startPrank(users.alice);
        expectedAssets = vault.previewRedeem(sharesAlice);
        assets = vault.redeem(sharesAlice, users.alice, users.alice);
        assertEq(assets, expectedAssets);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedAssets = vault.previewRedeem(sharesBob);
        assets = vault.redeem(sharesBob, users.bob, users.bob);
        assertEq(assets, expectedAssets);
        vm.stopPrank();
        vm.revertTo(snapshotId);
    }

    function testMaxApyVaultV2_ERC4626__PreviewWithdraw() public {
        vault.addStrategy(address(strategy0), 4000, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy1), 5000, type(uint72).max, 0, 0);

        /// ⭕️ SCENARIO 1: withdraw when all the funds are in the vault
        /// - Alice deposits 200 USDC
        /// - Bob deposits 5,000 USDC
        /// - Alice and Bob withdraw
        vault.deposit(200 * _1_USDC, users.alice);
        // other users deposits as well
        deal(USDC, users.bob, 5000 * _1_USDC);

        vm.startPrank(users.bob);
        IERC20(USDC).approve(address(vault), type(uint256).max);
        vault.deposit(5000 * _1_USDC, users.bob);
        vm.stopPrank();

        vm.startPrank(users.alice);
        uint256 snapshotId = vm.snapshot();
        uint256 expectedShares = vault.previewWithdraw(200 * _1_USDC);
        uint256 shares = vault.withdraw(200 * _1_USDC, users.alice, users.alice);
        assertEq(shares, expectedShares);

        vm.startPrank(users.bob);
        expectedShares = vault.previewWithdraw(4000 * _1_USDC);
        shares = vault.withdraw(4000 * _1_USDC, users.bob, users.bob);
        assertEq(shares, expectedShares);
        vm.stopPrank();

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 2: withdraw when some funds are in strategies
        /// - Alice deposits 200 USDC
        /// - Bob deposits 5,000 USDC
        /// - Harvest strategies so they take the vault money
        /// - Alice and Bob withdraw
        vm.startPrank(users.keeper);
        strategy0.harvest(0, 0);
        vm.stopPrank();
        vm.startPrank(users.alice);
        expectedShares = vault.previewWithdraw(180 * _1_USDC);
        shares = vault.withdraw(180 * _1_USDC, users.alice, users.alice);
        assertEq(shares, expectedShares);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedShares = vault.previewWithdraw(4000 * _1_USDC);
        shares = vault.withdraw(4000 * _1_USDC, users.bob, users.bob);
        assertEq(shares, expectedShares);
        vm.stopPrank();
        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3: withdraw when some funds are in strategies and they have profits
        /// - Alice deposits 200 USDC
        /// - Bob deposits 5,000 USDC
        /// - Harvest strategies so they take the vault money
        /// - Strategies make profit
        /// - Harvest again
        /// - Alice and Bob withdraw
        vm.startPrank(users.keeper);
        strategy0.harvest(0, 0);
        deal(USDC, address(strategy0), 50 * _1_USDC);
        strategy0.harvest(0, 0);
        vm.stopPrank();
        vm.startPrank(users.alice);
        expectedShares = vault.previewWithdraw(190 * _1_USDC);
        shares = vault.withdraw(190 * _1_USDC, users.alice, users.alice);
        assertEq(shares, expectedShares);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedShares = vault.previewWithdraw(4000 * _1_USDC);
        shares = vault.withdraw(4000 * _1_USDC, users.bob, users.bob);
        assertEq(shares, expectedShares);
        vm.stopPrank();
        vm.revertTo(snapshotId);
    }

    /* function testMaxApyVaultV2_ERC4626__PreviewWithdraw_Fuzzy(uint256 amount) public {
        vm.assume(amount > _1_USDC /10 && amount < 10_000 * _1_USDC);
        vault.addStrategy(address(strategy0), 4000, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy1), 5000, type(uint72).max, 0, 0);

        vault.deposit(200 * _1_USDC, users.alice);
        // other users deposits as well
        vm.startPrank(users.bob);
        deal(USDC, users.bob, amount);
        IERC20(USDC).approve(address(vault), type(uint256).max);
        vault.deposit(amount, users.bob);
        vm.stopPrank();

        vm.startPrank(users.keeper);
        strategy0.harvest(0, 0);
        deal(USDC, address(strategy0), 50 * _1_USDC);
        strategy0.harvest(0, 0);
        vm.stopPrank();

        vm.startPrank(users.alice);
        uint256 expectedShares = vault.previewWithdraw(190 * _1_USDC);
        uint256 shares = vault.withdraw(190 * _1_USDC, users.alice, users.alice);
        assertEq(shares, expectedShares);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedShares = vault.previewWithdraw(amount * 90/100);
        shares = vault.withdraw(amount * 90/100, users.bob, users.bob);
        assertEq(expectedShares, shares);
        vm.stopPrank();
    } */

    function testMaxApyVaultV2_ERC4626__totalAssets() external {
        vault.addStrategy(address(strategy0), 4000, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy1), 5000, type(uint72).max, 0, 0);
        vault.deposit(200 * _1_USDC, users.alice);
        assertEq(vault.totalAssets(), 200 * _1_USDC);
        deal(USDC, address(vault), 5000 * _1_USDC);
        // sending assets directly to the vault doesnt work
        assertEq(vault.totalAssets(), 200 * _1_USDC);
        // if a strategy makes profit {totalAssets} increases
        deal(USDC, address(strategy0),50 * _1_USDC);
        assertEq(vault.totalAssets(), 250 * _1_USDC);

        // harvest to take the funds
        vm.startPrank(users.keeper);
        strategy0.harvest(0, 0, 0);
        strategy1.harvest(0, 0, 0);
        // totalAssets should change because now tokens are invested in external protocol and 
        // the position value can be slightly different from the initial invested
        assertApproxEq(vault.totalAssets(), 250 * _1_USDC, _1_USDC);
    }
    

    function testMaxApyVaultV2_ERC4626__sharePrice() external {
        vault.addStrategy(address(strategy0), 4000, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy1), 5000, type(uint72).max, 0, 0);
        vault.deposit(200 * _1_USDC, users.alice);
        assertEq(vault.sharePrice(), _1_USDC);
        assertEq(strategy0.estimatedTotalAssets() , 0);
        assertEq(strategy1.estimatedTotalAssets() , 0);
        assertEq(strategy0.lastEstimatedTotalAssets() , 0);
        assertEq(strategy1.lastEstimatedTotalAssets() , 0);
        deal(USDC, address(vault), 5000 * _1_USDC);
        // sending assets directly to the vault doesnt work
        assertEq(vault.sharePrice(), _1_USDC);
        // if someone sends tokens to the strategy when it hasnt harvested yet
        // the amount is not accounted as estimated strategy assets
        deal(USDC, address(strategy0),50 * _1_USDC);
        assertEq(strategy0.estimatedTotalAssets() , 0);
        assertEq(strategy1.lastEstimatedTotalAssets() , 0);
        // profit is 50 out of 200 = 25% so share price is 1.25 USDC
        assertEq(vault.sharePrice(),_1_USDC);// round down
        // harvest to take the funds
        vm.startPrank(users.keeper);
        strategy0.harvest(0, 0, 0);
        strategy1.harvest(0, 0, 0);
        // after the first harvest the {lastEstimatedTotalAssets} should be set initialized
        assertGt(strategy0.lastEstimatedTotalAssets() , 0);
        assertGt(strategy1.lastEstimatedTotalAssets() , 0);
        // sharePrice increases because the 50 USDC sent before are included now
        uint256 sharePrice = vault.sharePrice();
        assertApproxEq(sharePrice, 125 * _1_USDC / 100, _1_USDC / 100);
        // if one strategy makes more profit  the share price should not change until we harvest 
        deal(USDC, address(strategy1), 50 * _1_USDC);
        assertEq(vault.sharePrice(), sharePrice);
        // if one strategy's totalAssets are reduced share price decreses
        uint256 estimatedTotalAssetsBefore = strategy0.estimatedTotalAssets();
        (uint256 liquidated, ) = strategy0.liquidatePosition(50 * _1_USDC);
        vm.startPrank(address(strategy0));
        IERC20(USDC).transfer(makeAddr("random"), liquidated);
        vm.stopPrank();
        assertApproxEq(vault.sharePrice(), _1_USDC, _1_USDC / 100);
        uint256 estimatedTotalAssetsAfter = strategy0.estimatedTotalAssets();
        assertLt(estimatedTotalAssetsAfter, estimatedTotalAssetsBefore);
        // if we harvest again the 50 USDC sent to one strategy will make share price increase again
        vm.startPrank(users.keeper);
        strategy1.harvest(0,0,0);
        assertApproxEq(sharePrice, 125 * _1_USDC / 100, _1_USDC / 100);
    }
}
