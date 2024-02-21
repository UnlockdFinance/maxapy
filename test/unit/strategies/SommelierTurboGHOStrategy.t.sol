// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import {BaseTest, IERC20, Vm, console} from "../../base/BaseTest.t.sol";
import {IStrategyWrapper} from "../../interfaces/IStrategyWrapper.sol";
import {IMaxApyVaultV2} from "src/interfaces/IMaxApyVaultV2.sol";
import {ICellar} from "src/interfaces/ICellar.sol";
import {SommelierTurboGHOStrategyWrapper} from "../../mock/SommelierTurboGHOStrategyWrapper.sol";
import {MaxApyVaultV2} from "src/MaxApyVaultV2.sol";
import {StrategyData} from "src/helpers/VaultTypes.sol";
import {SommelierTurboGHOStrategy} from "src/strategies/USDC/sommelier/SommelierTurboGHOStrategy.sol";
import {StrategyEvents} from "../../helpers/StrategyEvents.sol";

contract SommelierTurboGHOStrategyTest is BaseTest, StrategyEvents {
    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////
    address public constant CELLAR_USDC_MAINNET = 0x0C190DEd9Be5f512Bd72827bdaD4003e9Cc7975C;
    address public TREASURY;
    uint256 public _1_USDC = 1e6;

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy;
    SommelierTurboGHOStrategyWrapper public implementation;
    MaxApyVaultV2 public vaultDeployment;
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
        vaultDeployment = new MaxApyVaultV2(USDC, "MaxApyUSDCVault", "maxApy", TREASURY);

        vault = IMaxApyVaultV2(address(vaultDeployment));
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin();
        /// Deploy strategy implementation
        implementation = new SommelierTurboGHOStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        /// Deploy transparent upgradeable proxy
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Real USD Strategy")),
                users.alice,
                CELLAR_USDC_MAINNET
            )
        );
        vm.label(CELLAR_USDC_MAINNET, "Cellar");
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierTurboGHOStrategy");
        vm.label(address(USDC), "USDC");

        strategy = IStrategyWrapper(address(_proxy));

        /// Alice approves vault for deposits
        IERC20(USDC).approve(address(vault), 0);
        IERC20(USDC).approve(address(vault), type(uint256).max);
        vm.rollFork(18609089);
    }

    /*==================INITIALIZATION TESTS===================*/

    ////////////////////////////////////////////////////////////////
    ///                  TEST initialize()                       ///
    ////////////////////////////////////////////////////////////////

    function testSommelierTurboGHO__Initialization() public {
        /// *************** sommelier Strategy initialization *************** ///
        /// Deploy MaxApyVaultV2
        MaxApyVaultV2 _vault = new MaxApyVaultV2(USDC, "MaxApyUSDCVault", "maxUSDC", TREASURY);
        /// Deploy transparent upgradeable proxy admin
        ProxyAdmin _proxyAdmin = new ProxyAdmin();
        /// Deploy strategy implementation
        SommelierTurboGHOStrategyWrapper _implementation = new SommelierTurboGHOStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        /// Deploy transparent upgradeable proxy
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(_vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                users.alice,
                CELLAR_USDC_MAINNET
            )
        );
        ITransparentUpgradeableProxy proxyInit = ITransparentUpgradeableProxy(address(_proxy));

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));

        /// *************** Tests *************** ///

        /// Assert vault is set to MaxApy vault deployed in setup
        assertEq(_strategy.vault(), address(_vault));
        /// Assert maxapy vault obtains `VAULT_ROLE`
        assertEq(_strategy.hasAnyRole(_strategy.vault(), _strategy.VAULT_ROLE()), true);
        /// Assert underlying asset is set to USDC
        assertEq(_strategy.underlyingAsset(), USDC);
        /// Assert strategy has approved vault to transfer underlying
        assertEq(IERC20(USDC).allowance(address(_strategy), address(_vault)), type(uint256).max);
        /// Assert keeper user has `KEEPER_ROLE` granted
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        /// Assert alice (deployer) has `ADMIN_ROLE` granted
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);
        /// Assert strategy name is correct
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy Sommelier Strategy")));
        /// Assert underlying asset is set to CELLAR_USDC_MAINNET
        assertEq(_strategy.cellar(), CELLAR_USDC_MAINNET);
        /// Assert strategy has approved cellar to transfer underlying
        assertEq(IERC20(USDC).allowance(address(_strategy), CELLAR_USDC_MAINNET), type(uint256).max);

        /// *************** Proxy values *************** ///
        /// Assert proxy admin contract owner is set to deployer (alice)
        assertEq(_proxyAdmin.owner(), users.alice);
        /// Assert proxy admin is set to the proxy admin contract
        vm.startPrank(address(_proxyAdmin));
        assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///                   TEST setEmergencyExit()                ///
    ////////////////////////////////////////////////////////////////

    function testSommelierTurboGHO__SetEmergencyExit() public {
        /// Test unauthorized access with a user without privileges
        vm.stopPrank();
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setEmergencyExit(2);
        /// Test unauthorized access with a user with `VAULT_ROLE`
        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setEmergencyExit(2);

        /// Test proper emergency exit setting
        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit StrategyEmergencyExitUpdated(address(strategy), 2);
        strategy.setEmergencyExit(2);
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST isActive()                      ///
    ////////////////////////////////////////////////////////////////
    function testSommelierTurboGHO__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDC, address(strategy), 1 * _1_USDC);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(ICellar(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(USDC).transfer(makeAddr("random"), IERC20(USDC).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(USDC, address(strategy), 1 * _1_USDC);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0);
        assertEq(strategy.isActive(), true);
    }

    ////////////////////////////////////////////////////////////////
    ///                    TEST setStrategist()                  ///
    ////////////////////////////////////////////////////////////////
    function testSommelierTurboGHO__SetStrategist() public {
        // Negatives
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setStrategist(address(0));

        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAddress()"));
        strategy.setStrategist(address(0));

        // Positives
        address random = makeAddr("random");
        vm.expectEmit();
        emit StrategistUpdated(address(strategy), random);
        strategy.setStrategist(random);
        assertEq(strategy.strategist(), random);
    }

    /*==================STRATEGY CORE LOGIC TESTS==================*/
    ////////////////////////////////////////////////////////////////
    ///                      TEST slippage                       ///
    ////////////////////////////////////////////////////////////////
    function testSommelierTurboGHO__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// 1. Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, 10_000);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _prepareReturn()                  ///
    ////////////////////////////////////////////////////////////////

    function testSommelierTurboGHO__PrepareReturn() public {
        /// ⭕️ SCENARIO 1:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 40 * _1_USDC
        ///     - `totalAssets` = 40 * _1_USDC
        ///     - `shares` = 0
        ///     - `debt` = 40 * _1_USDC
        /// 2. Expected outcome:
        ///     - 2.1 Strategy has obtained profit, calculate profit.
        ///     - 2.2 Profit is 0 (not gt `underlyingBalance`) -> skip divesting from sommelier vault
        /// 3. Expected return values:
        ///     - `profit` -> 0
        ///     - `loss` -> 0
        ///     - `debtPayment` -> 1 * _1_USDC (value passed as `debtOutstanding`)
        /// Add strategy to vault
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0);

        /// there are no profits so setting the harvest to 50% wont have any effect
        (uint256 realizedProfit, uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDC, 0, 5_000);
        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, _1_USDC);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 2:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 40 * _1_USDC
        ///     - `totalAssets` = around 99.999 * _1_USDC
        ///     - `shares` = around 57.69
        ///     - `debt` = 40 * _1_USDC
        /// 2. Expected outcome:
        ///     - 2.1 Strategy has obtained profit, calculate profit.
        ///     - 2.2 Profit is around 60 USDC (it is greater than `underlyingBalance`)
        ///            -> divest from sommelier vault to obtain an extra 60 USDC
        ///     - 2.3 `amountToWithdraw` is 60 USDC, strategy holds 40 USDC already
        ///            -> `expectedAmountToWithdraw` is 20 USDC
        ///     - 2.4 Divesting causes 1 wei loss
        ///     - 2.5 `profit` >= `loss` -> profit -= loss;
        /// 3. Expected return values:
        ///     - `profit` -> around 60 USDC
        ///     - `loss` -> 0
        ///     - `debtPayment` -> 1 * _1_USDC (value passed as `debtOutstanding`)
        snapshotId = vm.snapshot();

        deal({token: USDC, to: address(strategy), give: 60 * _1_USDC});
        /// Perform initial 60 USDC investment in sommelier from the strategy side
        strategy.investSommelier(60 * _1_USDC);

        /// Add stategy to vault with 40% cap
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit 10 * _1_USDC into vault
        vault.deposit(100 * _1_USDC, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 10_000);
        // 60 USDC - losses from the previous 10 USDC investment
        assertEq(realizedProfit, 59875138); // 59.81 USDC
        assertEq(unrealizedProfit, 59906244); // 59.81 USDC
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 1_000);
        assertEq(realizedProfit, 5990624); // 5.9 USDC
        assertEq(unrealizedProfit, 59906244); // 59.81 USDC
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 0);
        assertEq(realizedProfit, 0); // 0
        assertEq(unrealizedProfit, 59906244); // 59.81 USDC
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 30 * _1_USDC (10 USDC lost)
        ///     - `totalAssets` = 30 * _1_USDC
        ///     - `shares` = 0
        ///     - `debt` = 40 * _1_USDC
        /// 2. Expected outcome:
        ///     - 2.1 Strategy has incurred a loss
        ///     - 2.2 Calculate loss with `debt - totalAssets` (40 USDC - 30 USDC = 10 USDC)
        snapshotId = vm.snapshot();
        vm.startPrank(users.alice);
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0);

        /// Fake strategy loss of 10 ETH
        strategy.triggerLoss(10 * _1_USDC);

        /// no realizedProfit was made, setting the harvest to 20% has no effect
        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 2_000);

        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDC);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _adjustPosition()                 ///
    ////////////////////////////////////////////////////////////////
    function testSommelierTurboGHO__AdjustPosition() public {
        /// Test if `_underlyingBalance()` is 0, no investment is performed
        strategy.adjustPosition();
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), 0);

        /// Perform 10 USDC investment
        deal({token: USDC, to: address(strategy), give: 10 * _1_USDC});
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));

        /// Perform 100 USDC investment
        deal({token: USDC, to: address(strategy), give: 100 * _1_USDC});
        expectedShares += strategy.sharesForAmount(100 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 100 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));

        /// Perform 500 USDC investment
        deal({token: USDC, to: address(strategy), give: 500 * _1_USDC});
        expectedShares += strategy.sharesForAmount(500 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 500 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _invest()                         ///
    ////////////////////////////////////////////////////////////////
    function testSommelierTurboGHO__Invest() public {
        /// Test if `amount` is 0, no investment is performed
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), 0);

        /// Test if `amount` is gt `_underlyingBalance()`, NotEnoughFundsToInvest() is thrown
        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        /// Perform 10 USDC investment
        deal({token: USDC, to: address(strategy), give: 10 * _1_USDC});
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _divest()                         ///
    ////////////////////////////////////////////////////////////////
    function testSommelierTurboGHO__Divest() public {
        /// Perform 1000 USDC investment
        deal({token: USDC, to: address(strategy), give: 10 * _1_USDC});
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        uint256 amountExpectedFromShares = strategy.shareValue(expectedShares);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));

        /// Divest
        uint256 strategyBalanceBefore = IERC20(USDC).balanceOf(address(strategy));
        uint256 expectedAmountDivested = strategy.previewWithdraw(amountExpectedFromShares);
        uint256 amountDivested = strategy.divest(strategy.sharesForAmount(amountExpectedFromShares));
        assertEq(amountDivested, expectedAmountDivested, "divested");
        assertEq(IERC20(USDC).balanceOf(address(strategy)) - strategyBalanceBefore, expectedAmountDivested, "balance");
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidatePosition()                  ///
    ////////////////////////////////////////////////////////////////

    function testSommelierTurboGHO__LiquidatePosition() public {
        /// Liquidate position where underlying balance can cover liquidation
        /// Scenario 1
        deal({token: USDC, to: address(strategy), give: 10 * _1_USDC});
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 * _1_USDC);
        assertEq(liquidatedAmount, 1 * _1_USDC);
        assertEq(loss, 0);

        /// Scenario 2
        (liquidatedAmount, loss) = strategy.liquidatePosition(10 * _1_USDC);
        assertEq(liquidatedAmount, 10 * _1_USDC);
        assertEq(loss, 0);

        /// Liquidate position where underlying balance can't cover liquidation
        /// Scenario 1
        deal({token: USDC, to: address(strategy), give: 5 * _1_USDC});
        // 
        strategy.invest(5 * _1_USDC, 0);
        deal({token: USDC, to: address(strategy), give: 10 * _1_USDC});

        (liquidatedAmount, loss) = strategy.liquidatePosition(15 * _1_USDC);

        uint256 expectedLiquidatedAmount = 10 * _1_USDC + strategy.shareValue(strategy.sharesForAmount(5 * _1_USDC));
        assertEq(liquidatedAmount, expectedLiquidatedAmount);
        /// 14.99 * _1_USDC
        assertEq(loss, 15 * _1_USDC - expectedLiquidatedAmount);

        /// Scenario 2
        deal({token: USDC, to: address(strategy), give: 1000 * _1_USDC});
        strategy.invest(1000 * _1_USDC, 0);
        deal({token: USDC, to: address(strategy), give: 500 * _1_USDC});
        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 * _1_USDC);

        expectedLiquidatedAmount = 500 * _1_USDC + strategy.shareValue(strategy.sharesForAmount(500 * _1_USDC));
        assertEq(liquidatedAmount, expectedLiquidatedAmount);
        /// 14.99 * _1_USDC
        assertEq(loss, 1000 * _1_USDC - expectedLiquidatedAmount);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidateAllPositions()              ///
    ////////////////////////////////////////////////////////////////
    function testSommelierTurboGHO__LiquidateAllPositions() public {
        /// Perform 10 USDC investment
        deal({token: USDC, to: address(strategy), give: 10 * _1_USDC});
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));

        /// Liquidate
        uint256 strategyBalanceBefore = IERC20(USDC).balanceOf(address(strategy));

        uint256 amountFreed = strategy.liquidateAllPositions();
        uint256 expectedAmountFreed = strategy.shareValue(strategy.sharesForAmount(10 * _1_USDC));
        assertEq(amountFreed, expectedAmountFreed);
        /// 1 wei loss divesting
        assertEq(IERC20(USDC).balanceOf(address(strategy)), strategyBalanceBefore + expectedAmountFreed);
        /// 1 wei loss divesting
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), 0);

        /// Perform 500 USDC investment
        deal({token: USDC, to: address(strategy), give: 500 * _1_USDC});
        expectedShares = strategy.sharesForAmount(500 * _1_USDC);
        strategy.invest(500 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));

        /// Liquidate
        strategyBalanceBefore = IERC20(USDC).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        expectedAmountFreed = strategy.shareValue(strategy.sharesForAmount(500 * _1_USDC));
        assertEq(amountFreed, expectedAmountFreed);
        /// 1 wei loss divesting
        assertEq(IERC20(USDC).balanceOf(address(strategy)), strategyBalanceBefore + expectedAmountFreed);
        /// 1 wei loss divesting
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST harvest()                       ///
    ////////////////////////////////////////////////////////////////
    function testSommelierTurboGHO__Harvest() public {
        /// Try to harvest not being keeper
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, 0);

        /// ⭕️ SCENARIO 1:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy earns 10 USDC. Strategy performs second harvest to request more funds.
        /// Dust in `_shareBalance()` makes it compulsory to transfer 9.99 USDC to vault, instead of 10 USDC

        uint256 snapshotId = vm.snapshot();

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        // esto para cuando haces harvest
        emit StrategyReported(
            address(strategy),
            0,
            /// vault realized gain
            0,
            /// vault unrealized gain
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain
            0,
            /// strategy loss
            uint128(40 * _1_USDC),
            /// strategy total debt
            uint128(40 * _1_USDC),
            /// credit 40 * _1_USDC due to transferring funds from vault to strategy
            4000
            /// debtratio not changed
        );
        vm.stopPrank();
        /// debtratio not changed
        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 USDC
        strategy.harvest(0, 0, 0);

        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        // there are 60 USDC left in the vault
        assertEq(IERC20(USDC).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(strategy)), 0);
        // strategy has expectedStrategyShareBalance cellar shares
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        /// 2. Strategy takes 10 USDC profit
        /// Fake gains in strategy (10 USDC = 40 USDC transferred previously + 10 USDC gains)
        // strategy gets 10 USDC more as profit
        deal({token: USDC, to: address(strategy), give: 10 * _1_USDC});
        uint256 beforeReportSnapshotId = vm.snapshot();
        /// Case #1: We harvest 100% of profit
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            10 * _1_USDC,
            /// vault realized gain - 10 USDC
            10 * _1_USDC,
            /// vault unrealized gain - 10 USDC
            0,
            /// vault loss
            0,
            /// vault debtPayment
            uint128(10 * _1_USDC),
            /// realized strategy gain - 10 USDC
            0,
            /// strategy loss
            uint128(40 * _1_USDC),
            /// strategy total debt: not changing now
            0,
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            4000
            /// debtratio not changed
        );

        vm.expectEmit();
        emit Harvested(10 * _1_USDC, 0, 0, 0);
        /// 10 USDC harvested
        strategy.harvest(0, 0, 10_000);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 70 * _1_USDC); // 70 USDC
        assertEq(IERC20(USDC).balanceOf(address(strategy)), 0);
        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);
        vm.revertTo(beforeReportSnapshotId);

        /// Case #2: We harvest 0% of profit
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault realized gain - 0 USDC
            0,
            /// vault unrealized gain - 10 USDC
            10 * _1_USDC,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// realized strategy gain - 0 USDC
            0,
            /// strategy loss
            0,
            /// strategy total debt: not changing now
            uint128(40 * _1_USDC),
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            0,
            4000
        );
        /// debtratio not changed

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        /// 0 USDC harvested
        strategy.harvest(0, 0, 0);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(strategy)), 0);
        /// 10 USDC  increase in regarding before
        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC + (10 * _1_USDC));
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);
        vm.revertTo(beforeReportSnapshotId);

        /// Case #3: We harvest 72.33% of profit
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            uint128(10 * _1_USDC * 7_233 / 10000),
            /// vault gain - 7.23 USDC
            10 * _1_USDC,
            /// vault unrealized gain - 10 USDC
            0,
            /// vault loss
            0,
            /// vault debtPayment
            uint128(10 * _1_USDC * 7_233 / 10000),
            /// realized strategy gain - 7.23 USDC
            0,
            /// strategy loss
            uint128(40 * _1_USDC),
            /// strategy total debt: not changing now
            0,
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            4000
            /// debtratio not changed
        );

        vm.expectEmit();
        emit Harvested((10 * _1_USDC * 7_233 / 10000), 0, 0, 0);
        /// 7.23 USDC harvested

        /// harvest 72.33% of the profit
        strategy.harvest(0, 0, 7_233);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 60 * _1_USDC + (10 * _1_USDC * 7_233 / 10000));
        assertEq(IERC20(USDC).balanceOf(address(strategy)), 0);
        expectedStrategyShareBalance =
            strategy.sharesForAmount(40 * _1_USDC + (10 * _1_USDC - (10 * _1_USDC * 7_233 / 10000)));
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);
        vm.revertTo(beforeReportSnapshotId);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        /// ⭕️ SCENARIO 2:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Emergency exit is activated
        /// 2. Strategy earns 10 USDC. Strategy performs second harvest to request more funds.
        /// Due to emergency mode, all funds are returned back to vault
        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        /// Step #1
        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// realized vault gain
            0,
            /// unrealized vault gain
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// realized strategy gain
            0,
            /// strategy loss
            uint128(40 * _1_USDC),
            /// strategy total debt
            uint128(40 * _1_USDC),
            /// credit 40 * USDC due to transferring funds from vault to strategy
            4000
            /// debtratio not changed
        );

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, 0);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        /// Step #2
        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        /// Step #3
        vm.startPrank(users.keeper);

        /// Fake gains in strategy (10 USDC = 40 USDC transferred previously + 10 USDC gains)
        deal({token: USDC, to: address(strategy), give: 10 * _1_USDC});

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            49937496,
            /// realized vault gain
            0,
            /// unrealized vault gain
            0,
            /// vault loss
            0,
            /// vault debtPayment
            49937496,
            /// realized strategy gain - 9.99 USDC
            0,
            /// strategy loss
            uint128(40 * _1_USDC),
            /// strategy total debt: not changing now
            0,
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            4000
        );
        /// debtratio not changed

        vm.expectEmit();
        emit Harvested(49937496, 0, 0, 0);
        /// 49.99 USDC harvested
        /// no effect since the strategy is in emergency exit
        strategy.harvest(0, 0, 2_000);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 109937496); // 109.93 USDC
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy loses 10 USDC. Strategy performs second harvest and its debt ratio gets reduced
        /// Dust in `_shareBalance()` makes it compulsory to transfer 9.99 USDC to vault, instead of 10 USDC

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// realized vault gain
            0,
            /// unrealized vault gain
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// realized strategy gain
            0,
            /// strategy loss
            uint128(40 * _1_USDC),
            /// strategy total debt
            uint128(40 * _1_USDC),
            /// credit 40 * _1_USDC due to transferring funds from vault to strategy
            4000
        );
        /// debtratio not changed

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, 0);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        /// 2. Strategy loses 10 USDC
        /// - Expected a 1000 reduction in debt ratio, 30% of total funds should be in the strategy
        /// - Total funds are now 90 USDC, 30% of which must be in strategy
        /// - 30% of 90 USDC = 27 USDC, but strategy still has 30 USDC -> there is a debt outstanding of 3 USDC

        /// Fake loss in strategy(shares are sent to a random address)
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);

        vm.startPrank(address(strategy));
        IERC20(CELLAR_USDC_MAINNET).transfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// realized vault gain
            0,
            /// unrealized vault gain
            9984374,
            /// vault loss - 9.984374 USDC
            0,
            /// vault debtPayment
            0,
            /// realized strategy gain
            9984374,
            /// strategy loss - 9.984374 USDC
            30015626,
            /// strategy total debt: 10 USDC less than initial debt
            0,
            /// credit 0 USDC due to transferring funds from strategy to vault
            3002
        );
        /// debtratio reduced

        vm.expectEmit();
        emit Harvested(0, 9984374, 0, 2992936);
        /// 10 USDC loss
        /// only losses, no effect
        strategy.harvest(0, 0, 1_000);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3002);
        assertEq(vault.totalDebt(), 30015626);
        assertEq(data.strategyDebtRatio, 3002);
        assertEq(data.strategyTotalDebt, 30015626);
        assertEq(data.strategyTotalLoss, 9984374);
    }


    ////////////////////////////////////////////////////////////////
    ///                     TEST previewWithdraw()               ///
    ////////////////////////////////////////////////////////////////
    function testSommelierTurboGHO__PreviewWithraw() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC + 23423,users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0);
        vm.stopPrank();
        uint256 expected = strategy.previewWithdraw(23489392);
        vm.startPrank(address(vault));
        uint256 loss = strategy.withdraw(23489392);
        assertEq(expected, 23489392 - loss);
    }

/*     function testSommelierTurboGHO__PreviewWithraw__FUZZY(uint256 amount) public {
        vm.assume(amount >= _1_USDC && amount <= 1_000_000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDC, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0);
        vm.stopPrank();
        uint256 expected = strategy.previewWithdraw(amount);
        vm.startPrank(address(vault));
        uint256 loss = strategy.withdraw(amount);
        assertEq(expected, amount - loss);
    }   */ 

    ////////////////////////////////////////////////////////////////
    ///                     TEST previewWithdrawRequest()        ///
    ////////////////////////////////////////////////////////////////
    function testSommelierTurboGHO__PreviewWithrawRequest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC + 23423,users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0);
        vm.stopPrank();                                          
        uint256 requestedAmount = strategy.previewWithdrawRequest(30 * _1_USDC);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDC).balanceOf(address(vault));
        strategy.withdraw(requestedAmount);
        uint256 withdrawn = IERC20(USDC).balanceOf(address(vault)) - balanceBefore ;
        // expect a max of 1% precision loss
        assertApproxEq(withdrawn, 30 * _1_USDC, withdrawn / 100);
        // expect the strategy to never withdraw less than expected
        assertGe(withdrawn, 30 * _1_USDC);
    }

   /*  function testSommelierTurboGHO__PreviewWithrawRequest__FUZZY(uint256 amount) public {
        vm.assume(amount >= _1_USDC && amount <= 1_000_000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDC, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0);
        vm.stopPrank();                                          
        uint256 requestedAmount = strategy.previewWithdrawRequest(amount);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDC).balanceOf(address(vault));
        strategy.withdraw(requestedAmount);
        uint256 withdrawn = IERC20(USDC).balanceOf(address(vault)) - balanceBefore ;
        // expect a max of 1-2% precision loss
        assertApproxEq(withdrawn, amount, withdrawn/ 60);
        // expect the strategy to never withdraw less than expected
        assertGe(withdrawn, amount);
    } */
}
