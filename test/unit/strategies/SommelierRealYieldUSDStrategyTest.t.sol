// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import {BaseTest, IERC20, Vm, console} from "../../base/BaseTest.t.sol";
import {IStrategyWrapper} from "../../interfaces/IStrategyWrapper.sol";
import {IMaxApyVaultV2} from "../../../src/interfaces/IMaxApyVaultV2.sol";
import {SommelierRealYieldStrategyWrapper} from "../../mock/SommelierRealYieldStrategyWrapper.sol";
import {MaxApyVaultV2} from "../../../src/MaxApyVaultV2.sol";
import {StrategyData} from "../../../src/helpers/VaultTypes.sol";
import {SommelierRealYieldUSDStrategy} from "../../../src/strategies/sommelier/SommelierRealYieldUSDStrategy.sol";
import {YearnStrategyEvents} from "../../helpers/YearnStrategyEvents.sol";

contract SommelierRealYieldUSDStrategyTest is BaseTest, YearnStrategyEvents {
    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////
    address public constant CELLAR_USDC_MAINNET = 0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E;
    address public TREASURY;
    uint256 public _1_USDC = 1e6;

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy;
    SommelierRealYieldStrategyWrapper public implementation;
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
        implementation = new SommelierRealYieldStrategyWrapper();

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
        vm.label(address(proxy), "SommelierRealYieldUSDStrategy");
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

    function testSommelierRealYieldUSD__Initialization() public {
        /// *************** sommelier Strategy initialization *************** ///
        /// Deploy MaxApyVaultV2
        MaxApyVaultV2 _vault = new MaxApyVaultV2(USDC, "MaxApyUSDCVault", "maxUSDC", TREASURY);
        /// Deploy transparent upgradeable proxy admin
        ProxyAdmin _proxyAdmin = new ProxyAdmin();
        /// Deploy strategy implementation
        SommelierRealYieldStrategyWrapper _implementation = new SommelierRealYieldStrategyWrapper();

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

    function testSommelierRealYieldUSD__SetEmergencyExit() public {
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
    function testSommelierRealYieldUSD__IsActive() public {
        assertEq(strategy.isActive(), false);

        deal(USDC, address(strategy), 1);
        assertEq(strategy.isActive(), true);

        vm.startPrank(address(strategy));
        IERC20(USDC).transfer(makeAddr("random"), IERC20(USDC).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(USDC, address(strategy), 1 * _1_USDC);
        strategy.invest(1 * _1_USDC, 0);
        assertEq(strategy.isActive(), true);
    }

    ////////////////////////////////////////////////////////////////
    ///                    TEST setStrategist()                  ///
    ////////////////////////////////////////////////////////////////
    function testSommelierRealYieldUSD__SetStrategist() public {
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
    function testSommelierRealYieldUSD__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// 1. Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _prepareReturn()                  ///
    ////////////////////////////////////////////////////////////////
    function testSommelierRealYieldUSD__PrepareReturn() public {
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
        /// The strategy receives 40 USDC
        strategy.mockReport(0, 0, 0);

        (uint256 profit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDC, 0);
        assertEq(profit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, 1 * _1_USDC);

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
        /// Strategy gets 40 USDC debt
        strategy.mockReport(0, 0, 0);

        // expect it to revert if 24h not passed from last deposit
        vm.expectRevert(abi.encodeWithSignature("SharesLocked()"));
        strategy.prepareReturn(0, 0);

        // unlock shares with foundry cheatcodes
        _unlockShares();
        (profit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        assertEq(profit, 59999998); // 59.99 USDC
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

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0);

        /// Fake strategy loss of 10 USDC
        strategy.triggerLoss(10 * _1_USDC);

        (profit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertEq(profit, 0);
        assertEq(loss, 10 * _1_USDC);
        assertEq(debtPayment, 0);
    }

    function testSommelierRealYieldUSD__PrepareReturn_Compound() public {
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
        /// The strategy receives 40 USDC
        strategy.mockReport(0, 0, 0);

        (uint256 profit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDC, 0, 4_232); // no profit no effect
        assertEq(profit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, 1 * _1_USDC);

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
        /// Strategy gets 40 USDC debt
        strategy.mockReport(0, 0, 0);

        // expect it to revert if 24h not passed from last deposit
        vm.expectRevert(abi.encodeWithSignature("SharesLocked()"));
        strategy.prepareReturn(0, 0);

        // unlock shares with foundry cheatcodes
        _unlockShares();
        uint256 beforeReturnSnapshotId = vm.snapshot();

        (profit, loss, debtPayment) = strategy.prepareReturn(0, 0, 10_000);
        assertEq(profit, 59999998); // 59.99 USDC
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (profit, loss, debtPayment) = strategy.prepareReturn(0, 0, 0);
        assertEq(profit,0);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (profit, loss, debtPayment) = strategy.prepareReturn(0, 0, 8_001);
        assertEq(profit,48005998); // 48 USDC 
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

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

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0);

        /// Fake strategy loss of 10 USDC
        strategy.triggerLoss(10 * _1_USDC);

        (profit, loss, debtPayment) = strategy.prepareReturn(0, 0, 100); // no effect

        assertEq(profit, 0);
        assertEq(loss, 10 * _1_USDC);
        assertEq(debtPayment, 0);
    }


    ////////////////////////////////////////////////////////////////
    ///                   TEST _adjustPosition()                 ///
    ////////////////////////////////////////////////////////////////
    function testSommelierRealYieldUSD__AdjustPosition() public {
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
    function testSommelierRealYieldUSD__Invest() public {
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
    function testSommelierRealYieldUSD__Divest() public {
        /// Perform 1000 USDC investment
        deal({token: USDC, to: address(strategy), give: 10 * _1_USDC});
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        uint256 amountExpectedFromShares = strategy.shareValue(expectedShares);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));

        /// Divest

        // Expect it reverts if 24h not elapsed
        vm.expectRevert();
        strategy.divest(expectedShares);

        // Unlock shares with foundry cheatcodes
        _unlockShares();
        uint256 strategyBalanceBefore = IERC20(USDC).balanceOf(address(strategy));
        uint256 expectedAmountDivested = strategy.previewWithdraw(amountExpectedFromShares);
        uint256 amountDivested = strategy.divest(strategy.sharesForAmount(amountExpectedFromShares));
        assertEq(amountDivested, expectedAmountDivested, "divested");
        assertEq(IERC20(USDC).balanceOf(address(strategy)) - strategyBalanceBefore, expectedAmountDivested, "balance");
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidatePosition()                  ///
    ////////////////////////////////////////////////////////////////

    function testSommelierRealYieldUSD__LiquidatePosition() public {
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
        // invertiros
        strategy.invest(5 * _1_USDC, 0);
        deal({token: USDC, to: address(strategy), give: 10 * _1_USDC});

        // liquidate position when 24h not expired, should not revert, return 0,0 instead
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 * _1_USDC);

        assertEq(liquidatedAmount, 0);
        assertEq(loss, 0);

        _unlockShares();
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 * _1_USDC);

        uint256 expectedLiquidatedAmount = 10 * _1_USDC + strategy.shareValue(strategy.sharesForAmount(5 * _1_USDC));
        assertEq(liquidatedAmount, expectedLiquidatedAmount);
        /// 14.99 * _1_USDC
        assertEq(loss, 15 * _1_USDC - expectedLiquidatedAmount);

        /// Scenario 2
        deal({token: USDC, to: address(strategy), give: 1000 * _1_USDC});
        strategy.invest(1000 * _1_USDC, 0);
        deal({token: USDC, to: address(strategy), give: 500 * _1_USDC});
        _unlockShares();
        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 * _1_USDC);

        expectedLiquidatedAmount = 500 * _1_USDC + strategy.shareValue(strategy.sharesForAmount(500 * _1_USDC));
        assertEq(liquidatedAmount, expectedLiquidatedAmount);
        /// 14.99 * _1_USDC
        assertEq(loss, 1000 * _1_USDC - expectedLiquidatedAmount);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidateAllPositions()              ///
    ////////////////////////////////////////////////////////////////
    function testSommelierRealYieldUSD__LiquidateAllPositions() public {
        /// Perform 10 USDC investment
        deal({token: USDC, to: address(strategy), give: 10 * _1_USDC});
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));

        /// Liquidate
        uint256 strategyBalanceBefore = IERC20(USDC).balanceOf(address(strategy));

        // expect to revert if 24h not expired
        vm.expectRevert(abi.encodeWithSignature("SharesLocked()"));
        strategy.liquidateAllPositions();

        _unlockShares();
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
        _unlockShares();
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
    function testSommelierRealYieldUSD__Harvest() public {
        /// Try to harvest not being keeper
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0);

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
            /// vault gain
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain
            0,
            /// strategy loss
            uint128(40 * _1_USDC),
            /// strategy total debt
            uint128(40 * _1_USDC),
            /// credit 40 * _1_USDC due to transferring funds from vault to strategy
            4000
        );
        vm.stopPrank();
        /// debtratio not changed
        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 USDC
        strategy.harvest(0, 0);

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
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault gain - 9.99999 USDC
            9999999,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain - 9.99999 USDC
            9999999,
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
        emit Harvested(9999999, 0, 0, 0);
        /// 9.980 USDC harvested
        // expect to revert if shares are locked
        vm.expectRevert(abi.encodeWithSignature("SharesLocked()"));
        strategy.harvest(0, 0);

        // expect to revert if 3 days harvest interval not expired
        _unlockShares();
        vm.expectRevert(abi.encodeWithSignature("HarvestTimeNotElapsed()"));
        strategy.harvest(0, 0);

        // harbest successfully
        _unlockHarvest();
        strategy.harvest(0, 0);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 69999999); // 69.99 USDC
        assertEq(IERC20(USDC).balanceOf(address(strategy)), 0);
        /// 10 USDC  increase in regarding before
        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC + (10 * _1_USDC - 9999999));
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

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
            /// vault gain
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain
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

        _unlockShares();
        _unlockHarvest();
        strategy.harvest(0, 0);

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
            49999999,
            /// vault gain + all of strategy's funds (40 initial USDC + 9.999999 USDC gain)
            0,
            /// vault loss
            0,
            /// vault debtPayment
            49999999,
            /// strategy gain - 9.99999 USDC
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
        emit Harvested(49999999, 0, 0, 0);
        /// 49.99999 USDC harvested
        _unlockShares();
        _unlockHarvest();
        strategy.harvest(0, 0);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 109999999); // 109.99 USDC
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
            /// vault gain
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain
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

        strategy.harvest(0, 0);

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
        _unlockShares();
        IERC20(CELLAR_USDC_MAINNET).transfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// vault gain
            10000000,
            /// vault loss - 10000000
            0,
            /// vault debtPayment
            0,
            /// strategy gain
            10000000,
            /// strategy loss - 10 USDC
            30000000,
            /// strategy total debt: 10 USDC less than initial debt
            0,
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            3000
        );
        /// debtratio reduced

        vm.expectEmit();
        emit Harvested(0, 10000000, 0, 3000000);
        /// 10 USDC loss
        _unlockHarvest();
        strategy.harvest(0, 0);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(vault.totalDebt(), 30000000);
        assertEq(data.strategyDebtRatio, 3000);
        assertEq(data.strategyTotalDebt, 30000000);
        assertEq(data.strategyTotalLoss, 10000000);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// vault gain
            1,
            /// vault loss - 1 wei. This is due to the fact that strategy had to withdraw 3 USDC from sommelier (totalDebt should be 27 USDC but was 30 USDC), causing 1 wei loss
            2999999,
            /// vault debtPayment (3 USDC - 1 wei loss)
            0,
            /// strategy gain
            10000001,
            /// strategy loss - 10 USDC previously lost + 1 wei loss
            27000000,
            /// strategy total debt: 27 USDC, back to regular values
            0,
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            3000
        );
        /// debtratio: 30% of funds shared with strategy

        vm.expectEmit();
        emit Harvested(0, 1, 2999999, 1);
        /// 10 USDC loss

        uint256 vaultBalanceBefore = IERC20(USDC).balanceOf(address(vault));
        uint256 strategyBalanceBefore = IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy));
        uint256 expectedShareDecrease = strategy.sharesForAmount(2999999);
        _unlockHarvest();
        strategy.harvest(0, 0);

        data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(vault.totalDebt(), 27000000);
        assertEq(data.strategyDebtRatio, 3000);
        assertEq(data.strategyTotalDebt, 27000000);
        assertEq(data.strategyTotalLoss, 10000001);
        assertEq(IERC20(USDC).balanceOf(address(vault)), vaultBalanceBefore + 2999999);
        assertLe(
            IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore - expectedShareDecrease
        );
    }

    function testSommelierRealYieldUSD__Harvest_Compound() public {
        /// Try to harvest not being keeper
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0);

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
            /// vault gain
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain
            0,
            /// strategy loss
            uint128(40 * _1_USDC),
            /// strategy total debt
            uint128(40 * _1_USDC),
            /// credit 40 * _1_USDC due to transferring funds from vault to strategy
            4000
        );
        vm.stopPrank();
        /// debtratio not changed
        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 USDC
        strategy.harvest(0, 0);

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

        /// Case #1: harvest 100% of the profit
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault gain - 9.99999 USDC
            9999999,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain - 9.99999 USDC
            9999999,
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
        emit Harvested(9999999, 0, 0, 0);
        /// 9.980 USDC harvested
        // expect to revert if shares are locked
        vm.expectRevert(abi.encodeWithSignature("SharesLocked()"));
        strategy.harvest(0, 0);

        // expect to revert if 3 days harvest interval not expired
        _unlockShares();
        vm.expectRevert(abi.encodeWithSignature("HarvestTimeNotElapsed()"));
        strategy.harvest(0, 0);

        // harvest successfully
        _unlockHarvest();
        strategy.harvest(0, 0);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 69999999); // 69.99 USDC
        assertEq(IERC20(USDC).balanceOf(address(strategy)), 0);
        /// 10 USDC  increase in regarding before
        uint256 shares = strategy.sharesForAmount(10 * _1_USDC - 9999999);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance + shares);
        vm.revertTo(beforeReportSnapshotId);

        /// Case #2: harvest 0% of the profit
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault gain - 0 USDC
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain - 0 USDC
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
        // it shouldn't revert this time
        strategy.harvest(0, 0, 0);

        assertEq(IERC20(USDC).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(strategy)), 0);
        /// 10 USDC  increase in regarding before
        shares = strategy.sharesForAmount(10 * _1_USDC);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance + shares);
        vm.revertTo(beforeReportSnapshotId);

        /// Case #3: harvest 54.02% of the profit
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault gain - 5.4 USDC
            5401999,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain - 5.4 USDC
            5401999,
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
        emit Harvested(5401999, 0, 0, 0);
        /// 9.980 USDC harvested
        // expect to revert if shares are locked
        vm.expectRevert(abi.encodeWithSignature("SharesLocked()"));
        strategy.harvest(0, 0);

        // expect to revert if 3 days harvest interval not expired
        _unlockShares();
        vm.expectRevert(abi.encodeWithSignature("HarvestTimeNotElapsed()"));
        strategy.harvest(0, 0);

        // harvest successfully
        _unlockHarvest();
        strategy.harvest(0, 0, 5402);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 60 * _1_USDC + 5401999);
        assertEq(IERC20(USDC).balanceOf(address(strategy)), 0);
        /// 10 USDC  increase in regarding before
        shares = strategy.sharesForAmount(10 * _1_USDC - 5401999);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance + shares);
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
            /// vault gain
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain
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

        _unlockShares();
        _unlockHarvest();
        strategy.harvest(0, 0);

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
            49999999,
            /// vault gain + all of strategy's funds (40 initial USDC + 9.999999 USDC gain)
            0,
            /// vault loss
            0,
            /// vault debtPayment
            49999999,
            /// strategy gain - 9.99999 USDC
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
        emit Harvested(49999999, 0, 0, 0);
        /// 49.99999 USDC harvested
        _unlockShares();
        _unlockHarvest();
        strategy.harvest(0, 0, 2834); // no effect
        assertEq(IERC20(USDC).balanceOf(address(vault)), 109999999); // 109.99 USDC
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
            /// vault gain
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain
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

        strategy.harvest(0, 0, 1293); // no effect

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
        _unlockShares();
        IERC20(CELLAR_USDC_MAINNET).transfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// vault gain
            10000000,
            /// vault loss - 10000000
            0,
            /// vault debtPayment
            0,
            /// strategy gain
            10000000,
            /// strategy loss - 10 USDC
            30000000,
            /// strategy total debt: 10 USDC less than initial debt
            0,
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            3000
        );
        /// debtratio reduced

        vm.expectEmit();
        emit Harvested(0, 10000000, 0, 3000000);
        /// 10 USDC loss
        _unlockHarvest();
        strategy.harvest(0, 0, 8932); // no effect

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(vault.totalDebt(), 30000000);
        assertEq(data.strategyDebtRatio, 3000);
        assertEq(data.strategyTotalDebt, 30000000);
        assertEq(data.strategyTotalLoss, 10000000);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// vault gain
            1,
            /// vault loss - 1 wei. This is due to the fact that strategy had to withdraw 3 USDC from sommelier (totalDebt should be 27 USDC but was 30 USDC), causing 1 wei loss
            2999999,
            /// vault debtPayment (3 USDC - 1 wei loss)
            0,
            /// strategy gain
            10000001,
            /// strategy loss - 10 USDC previously lost + 1 wei loss
            27000000,
            /// strategy total debt: 27 USDC, back to regular values
            0,
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            3000
        );
        /// debtratio: 30% of funds shared with strategy

        vm.expectEmit();
        emit Harvested(0, 1, 2999999, 1);
        /// 10 USDC loss

        uint256 vaultBalanceBefore = IERC20(USDC).balanceOf(address(vault));
        uint256 strategyBalanceBefore = IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy));
        uint256 expectedShareDecrease = strategy.sharesForAmount(2999999);
        _unlockHarvest();
        strategy.harvest(0, 0, 1231); // no effect

        data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(vault.totalDebt(), 27000000);
        assertEq(data.strategyDebtRatio, 3000);
        assertEq(data.strategyTotalDebt, 27000000);
        assertEq(data.strategyTotalLoss, 10000001);
        assertEq(IERC20(USDC).balanceOf(address(vault)), vaultBalanceBefore + 2999999);
        assertLe(
            IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore - expectedShareDecrease
        );
    }


    /// @notice directly write to the `userShareLockStartTime` mapping in the Sommelier cellar
    function _unlockShares() internal {
        vm.store(
            address(CELLAR_USDC_MAINNET), keccak256(abi.encode(address(strategy), uint256(22))), bytes32(uint256(0))
        );
    }

    function _lockShares() internal {
        vm.store(
            address(CELLAR_USDC_MAINNET),
            keccak256(abi.encode(address(strategy), uint256(22))),
            bytes32(uint256(block.timestamp))
        );
    }

    function _unlockHarvest() internal {
        vm.store(address(strategy), bytes32(uint256(28)), bytes32(uint256(block.timestamp - 259200)));
    }
}
