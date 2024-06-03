// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import { ICellar } from "src/interfaces/ICellar.sol";
import { ICurve } from "src/interfaces/ICurve.sol";
import { IWETH } from "src/interfaces/IWETH.sol";
import { BaseTest, IERC20, Vm, console } from "../../base/BaseTest.t.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { SommelierStEthDepositTurboStEthStrategyWrapper } from
    "../../mock/SommelierStEthDepositTurboStEthStrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { SommelierTurboStEthStrategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboStEthStrategy.sol";
import { StrategyEvents } from "../../helpers/StrategyEvents.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

contract SommelierStEthDepositTurboStEthStrategyTest is BaseTest, StrategyEvents {
    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////
    address public constant CELLAR_STETH_MAINNET = 0xc7372Ab5dd315606dB799246E8aA112405abAeFf;
    address public constant CURVE_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public TREASURY;

    ////////////////////////////////////////////////////////////////
    ///                      HELPER FUNCTION                     ///
    ////////////////////////////////////////////////////////////////

    function _dealStEth(address give, uint256 wethIn) internal returns (uint256 stEthOut) {
        vm.deal(give, wethIn);
        stEthOut = ICurve(CURVE_POOL).exchange{ value: wethIn }(0, 1, wethIn, 0);
        IERC20(ST_ETH_MAINNET).transfer(give, stEthOut >= wethIn ? wethIn : stEthOut);
    }

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy;
    SommelierStEthDepositTurboStEthStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function setUp() public {
        super._setUp("MAINNET");

        TREASURY = makeAddr("treasury");

        /// Deploy MaxApyVault
        vaultDeployment = new MaxApyVault(WETH_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin();
        /// Deploy strategy implementation
        implementation = new SommelierStEthDepositTurboStEthStrategyWrapper();

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
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                users.alice,
                CELLAR_STETH_MAINNET
            )
        );
        vm.label(CELLAR_STETH_MAINNET, "Cellar");
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierStEThDeposiTurbStEthStrategy");
        vm.label(WETH_MAINNET, "WETH");
        vm.label(ST_ETH_MAINNET, "StETH");
        vm.label(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022, "CurvePool");

        strategy = IStrategyWrapper(address(_proxy));

        /// Alice approves vault for deposits
        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
        vm.rollFork(18_958_838);
    }

    /*==================INITIALIZATION TESTS===================*/

    ////////////////////////////////////////////////////////////////
    ///                  TEST initialize()                       ///
    ////////////////////////////////////////////////////////////////

    function testSommelierStEthDeposit_TurboStEth__Initialization() public {
        /// *************** sommelier Strategy initialization *************** ///
        /// Deploy MaxApyVault
        MaxApyVault _vault = new MaxApyVault(WETH_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);
        /// Deploy transparent upgradeable proxy admin
        ProxyAdmin _proxyAdmin = new ProxyAdmin();
        /// Deploy strategy implementation
        SommelierStEthDepositTurboStEthStrategyWrapper _implementation =
            new SommelierStEthDepositTurboStEthStrategyWrapper();

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
                CELLAR_STETH_MAINNET
            )
        );
        ITransparentUpgradeableProxy proxyInit = ITransparentUpgradeableProxy(address(_proxy));

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));

        /// *************** Tests *************** ///

        /// Assert vault is set to MaxApy vault deployed in setup
        assertEq(_strategy.vault(), address(_vault));
        /// Assert maxapy vault obtains `VAULT_ROLE`
        assertEq(_strategy.hasAnyRole(_strategy.vault(), _strategy.VAULT_ROLE()), true);
        /// Assert underlying asset is set to WETH
        assertEq(_strategy.underlyingAsset(), WETH_MAINNET);
        /// Assert strategy has approved vault to transfer underlying
        assertEq(IERC20(WETH_MAINNET).allowance(address(_strategy), address(_vault)), type(uint256).max);
        /// Assert keeper user has `KEEPER_ROLE` granted
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        /// Assert alice (deployer) has `ADMIN_ROLE` granted
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);
        /// Assert strategy name is correct
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy Sommelier Strategy")));
        /// Assert underlying asset is set to CELLAR_STETH_MAINNET
        assertEq(_strategy.cellar(), CELLAR_STETH_MAINNET);
        /// Assert strategy has approved cellar to transfer underlying
        assertEq(IERC20(ST_ETH_MAINNET).allowance(address(_strategy), CELLAR_STETH_MAINNET), type(uint256).max);
        /// Assert `maxSingleTrade` is set to the expected value
        assertEq(_strategy.maxSingleTrade(), 1000 * 1e18);

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

    function testSommelierStEthDeposit_TurboStEth__SetEmergencyExit() public {
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
    function testSommelierStEthDeposit_TurboStEth__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(ICellar(CELLAR_STETH_MAINNET).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(WETH_MAINNET).transfer(makeAddr("random"), IERC20(WETH_MAINNET).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
        assertEq(strategy.isActive(), true);
    }

    ////////////////////////////////////////////////////////////////
    ///                  TEST setMaxSingleTrade()                ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__SetMaxSingleTrade() public {
        /// Test unauthorized access with a user without privileges
        vm.stopPrank();
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMaxSingleTrade(1 ether);

        /// Test unauthorized access with a user with `VAULT_ROLE`
        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMaxSingleTrade(1 ether);

        /// Test set 0 amount
        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAmount()"));
        strategy.setMaxSingleTrade(0);

        /// Test proper max single trade setting
        vm.expectEmit();
        emit MaxSingleTradeUpdated(1 ether);
        strategy.setMaxSingleTrade(1 ether);
        assertEq(strategy.maxSingleTrade(), 1 ether);
    }

    ////////////////////////////////////////////////////////////////
    ///                  TEST setMinSingleTrade()                ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__SetMinSingleTrade() public {
        /// Test unauthorized access with a user without privileges
        vm.stopPrank();
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 ether);

        /// Test unauthorized access with a user with `VAULT_ROLE`
        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 ether);

        /// Test proper min single trade setting
        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit MinSingleTradeUpdated(1 ether);
        strategy.setMinSingleTrade(1 ether);
        assertEq(strategy.minSingleTrade(), 1 ether);
    }

    ////////////////////////////////////////////////////////////////
    ///                    TEST setStrategist()                  ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__SetStrategist() public {
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
    function testSommelierStEthDeposit_TurboStEth__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// 1. Deposit into vault
        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, 10_000, address(0));
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _prepareReturn()                  ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__PrepareReturn() public {
        /// ⭕️ SCENARIO 1:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 40 ether
        ///     - `totalAssets` = 40 ether
        ///     - `shares` = 0
        ///     - `debt` = 40 ether
        /// 2. Expected outcome:
        ///     - 2.1 Strategy has obtained profit, calculate profit.
        ///     - 2.2 Profit is 0 (not gt `underlyingBalance`) -> skip divesting from sommelier vault
        /// 3. Expected return values:
        ///     - `profit` -> 0
        ///     - `loss` -> 0
        ///     - `debtPayment` -> 1 ether (value passed as `debtOutstanding`)
        /// Add strategy to vault
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0, TREASURY);

        /// there are no profits so setting the harvest to 50% wont have any effect
        (uint256 realizedProfit, uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) =
            strategy.prepareReturn(1 ether, 0, 5000);
        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, 1 ether);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 2:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 40 ether
        ///     - `totalAssets` = around 99.999 ether
        ///     - `shares` = around 57.69
        ///     - `debt` = 40 ether
        /// 2. Expected outcome:
        ///     - 2.1 Strategy has obtained profit, calculate profit.
        ///     - 2.2 Profit is around 60 ETH (it is greater than `underlyingBalance`)
        ///            -> divest from sommelier vault to obtain an extra 60 ETH
        ///     - 2.3 `amountToWithdraw` is 60 ETH, strategy holds 40 ETH already
        ///            -> `expectedAmountToWithdraw` is 20 ETH
        ///     - 2.4 Divesting causes 1 wei loss
        ///     - 2.5 `profit` >= `loss` -> profit -= loss;
        /// 3. Expected return values:
        ///     - `profit` -> around 60 ETH
        ///     - `loss` -> 0
        ///     - `debtPayment` -> 1 ether (value passed as `debtOutstanding`)
        snapshotId = vm.snapshot();

        /// Add stategy to vault with 40% cap
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        _dealStEth(address(strategy), 60 ether);
        /// Perform initial 60 USDC investment in sommelier from the strategy side
        strategy.investSommelier(60 ether);

        /// Deposit 10 ether into vault
        vault.deposit(100 ether, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0, TREASURY);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 10_000);

        assertEq(realizedProfit, 59.949949239970347554 ether);
        assertEq(unrealizedProfit, 59.967032154129262745 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 1000);

        assertEq(realizedProfit, 5.996703215412926274 ether);
        assertEq(unrealizedProfit, 59.967032154129262745 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 0);

        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 59.967032154129262745 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 30 ether (10 ETH lost)
        ///     - `totalAssets` = 30 ether
        ///     - `shares` = 0
        ///     - `debt` = 40 ether
        /// 2. Expected outcome:
        ///     - 2.1 Strategy has incurred a loss
        ///     - 2.2 Calculate loss with `debt - totalAssets` (40 ETH - 30 ETH = 10 ETH)
        snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0, TREASURY);

        /// Fake strategy loss of 10 ETH
        strategy.triggerLoss(10 ether);
        /// no realizedProfit was made, setting the harvest to 20% has no effect
        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 2000);

        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 ether);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 4:
        /// 1. Initial State: Vault has 100 ETH profit. Withdrawal from vault is limited to 1000 wei, so
        /// `profit` will be > than `underlyingBalance`, setting profit to balance value

        snapshotId = vm.snapshot();

        deal({ token: WETH_MAINNET, to: address(strategy), give: 80 ether });

        // Perform initial investment in sommelier from the strategy side
        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        /// Set `maxSingleTrade` to 1000 wei
        strategy.setMaxSingleTrade(1000);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0, TREASURY);

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 10_000);

        /// Assert realizedProfit is set to the underlying balance of the strategy
        /// (which is the 40 ETH debt from the vault + the 999 wei withdrawn (considering
        /// we tried to withdrew 1000 wei due to the `maxSingleTrade`))
        assertEq(realizedProfit, 40 ether + 999);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _adjustPosition()                 ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__AdjustPosition() public {
        /// Test if `_underlyingBalance()` is 0, no investment is performed
        strategy.adjustPosition();
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        /// Perform 10 ETH investment
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.adjustPosition();
        // will not get exactly the expected shares because there is a swap in between
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);

        /// Perform 100 ETH investment
        deal({ token: WETH_MAINNET, to: address(strategy), give: 100 ether });
        expectedShares += strategy.sharesForAmount(100 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 100 ether);
        strategy.adjustPosition();
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);

        /// Perform 500 ETH investment
        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });
        expectedShares += strategy.sharesForAmount(500 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 500 ether);
        strategy.adjustPosition();
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _invest()                         ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__Invest() public {
        /// Test if `amount` is 0, no investment is performed
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        /// Test if `amount` is gt `_underlyingBalance()`, NotEnoughFundsToInvest() is thrown
        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        /// Perform 10 ETH investment
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        // will not get exactly the expected shares because there is a swap in between
        assertApproxEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares, expectedShares / 100);

        /// Perform 10 ETH investment
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        expectedShares += strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);
    }

    function testSommelierStEthDeposit_TurboStEth__Invest_CellarIsShutdown() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 snapshotId = vm.snapshot();
        _shutDownCellar();
        // if cellar is shut down no funds are invested
        assertEq(strategy.invest(10 ether, 0), 0);
        vm.revertTo(snapshotId);
        assertGt(strategy.invest(10 ether, 0), 0);
    }

    function testSommelierStEthDeposit_TurboStEth__Invest_CellarIsPaused() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 snapshotId = vm.snapshot();
        _pauseCellar();
        // if cellar is shut down no funds are invested
        assertEq(strategy.invest(10 ether, 0), 0);
        vm.revertTo(snapshotId);
        assertGt(strategy.invest(10 ether, 0), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _divest()                         ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__Divest() public {
        /// Perform 1000 ETH investment
        deal({ token: WETH_MAINNET, to: address(strategy), give: 1000 ether });
        uint256 expectedShares = strategy.sharesForAmount(1000 ether);

        strategy.invest(1000 ether, 0);

        uint256 expectedAssets = strategy.shareValue(expectedShares);
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);

        /// Divest
        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        uint256 amountDivested = strategy.divest(expectedShares * 99 / 100);
        assertApproxEq(amountDivested, expectedAssets, expectedAssets / 100);
        assertApproxEq(
            IERC20(WETH_MAINNET).balanceOf(address(strategy)),
            strategyBalanceBefore + expectedAssets,
            expectedAssets / 100
        );
    }

    function testSommelierStEthDeposit_TurboStEth__Divest_CellarIsPaused() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        strategy.invest(10 ether, 0);
        uint256 snapshotId = vm.snapshot();
        _pauseCellar();
        // if cellar is paused no funds are divested
        assertEq(strategy.divest(1 ether), 0);
        vm.revertTo(snapshotId);
        assertGt(strategy.divest(1 ether), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidatePosition()                  ///
    ////////////////////////////////////////////////////////////////

    // TODO: remove dev comments
    function testSommelierStEthDeposit_TurboStEth__LiquidatePosition() public {
        /// Liquidate position where underlying balance can cover liquidation
        /// Scenario 1
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 ether);
        assertEq(liquidatedAmount, 1 ether);
        assertEq(loss, 0);

        /// Scenario 2
        (liquidatedAmount, loss) = strategy.liquidatePosition(10 ether);
        assertEq(liquidatedAmount, 10 ether);
        assertEq(loss, 0);

        /// Liquidate position where underlying balance can't cover liquidation
        /// Scenario 1
        deal({ token: WETH_MAINNET, to: address(strategy), give: 5 ether });
        strategy.invest(5 ether, 0);
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });

        uint256 expectedLiquidatedAmount = 10 ether + strategy.shareValue(strategy.sharesForAmount(5 ether));
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 ether);
        // will  not be exactly the same becasue there is a swap in between
        assertApproxEq(liquidatedAmount, expectedLiquidatedAmount, expectedLiquidatedAmount / 100);
        /// 14.99 ether
        assertApproxEq(loss, 15 ether - expectedLiquidatedAmount, expectedLiquidatedAmount / 100);

        /// Scenario 2
        deal({ token: WETH_MAINNET, to: address(strategy), give: 1000 ether });
        strategy.invest(1000 ether, 0);
        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });

        expectedLiquidatedAmount = 500 ether + strategy.shareValue(strategy.sharesForAmount(500 ether));

        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 ether);

        assertApproxEq(liquidatedAmount, expectedLiquidatedAmount, expectedLiquidatedAmount / 100);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidateAllPositions()              ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__LiquidateAllPositions() public {
        /// Perform 10 ETH investment
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        strategy.invest(10 ether, 0);
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);

        /// Liquidate
        uint256 expectedAmountFreed = strategy.shareValue(expectedShares);
        uint256 amountFreed = strategy.liquidateAllPositions();
        assertApproxEq(amountFreed, expectedAmountFreed, expectedAmountFreed / 100);
        assertApproxEq(
            IERC20(WETH_MAINNET).balanceOf(address(strategy)), expectedAmountFreed, expectedAmountFreed / 100
        );
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        /// Perform 500 ETH investment
        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });
        expectedShares = strategy.sharesForAmount(500 ether);
        strategy.invest(500 ether, 0);
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);

        /// Liquidate
        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        expectedAmountFreed = strategy.shareValue(expectedShares);
        amountFreed = strategy.liquidateAllPositions();
        assertApproxEq(amountFreed, expectedAmountFreed, expectedAmountFreed / 100);
        assertApproxEq(
            IERC20(WETH_MAINNET).balanceOf(address(strategy)),
            strategyBalanceBefore + expectedAmountFreed,
            expectedAmountFreed / 100
        );
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST harvest()                       ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__Harvest() public {
        /// Try to harvest not being keeper
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, 0, address(0));

        /// ⭕️ SCENARIO 1:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy earns 10 ETH. Strategy performs second harvest to request more funds.
        /// Dust in `_shareBalance()` makes it compulsory to transfer 9.99 ETH to vault, instead of 10 ETH

        uint256 snapshotId = vm.snapshot();

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// realized profit
            0,
            /// unrealized profit
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain
            0,
            /// strategy loss
            40 ether,
            /// strategy total debt
            40 ether,
            /// credit 40 ether due to transferring funds from vault to strategy
            4000
        );
        vm.stopPrank();
        /// debtratio not changed
        vm.startPrank(users.keeper);
        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, 0, address(0));

        // there are 60 eth left in the vault
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
        // strategy has expectedStrategyShareBalance cellar shares
        assertApproxEq(
            IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)),
            expectedStrategyShareBalance,
            expectedStrategyShareBalance / 100
        );

        /// 2. Strategy takes 10 ETH profit
        /// Fake gains in strategy (10 ETH = 40 ETH transferred previously + 10 ETH gains)
        // strategy gets 10 eth more as profit
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 beforeReportSnapshotId = vm.snapshot();

        /// Case #1: We harvest 100% of profit
        vm.expectEmit();
        // debt: 40 eth
        emit StrategyReported(
            address(strategy),
            /// vault realized gain - 10 ETH
            10 ether,
            /// vault unrealized gain - 10 ETH
            10 ether,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain - 10 ETH
            10 ether,
            /// strategy loss
            0,
            /// strategy total debt: not changing now
            40 ether,
            /// credit 0 ether due to transferring funds from strategy to vault
            0,
            4000
        );
        /// debtratio not changed
        vm.expectEmit();
        emit Harvested(10 ether, 0, 0, 0);
        /// 10 ETH harvested
        strategy.harvest(0, 0, 10_000, address(0));
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 70 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
        vm.revertTo(beforeReportSnapshotId);

        /// Case #2: We harvest 0% of profit
        vm.expectEmit();
        // debt: 40 eth
        emit StrategyReported(
            address(strategy),
            /// vault realized gain - 0
            0,
            /// vault unrealized gain - 10 ETH
            10 ether,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain - 10 ETH
            0,
            /// strategy loss
            0,
            /// strategy total debt: not changing now
            40 ether,
            /// credit 0 ether due to transferring funds from strategy to vault
            0,
            4000
        );
        /// debtratio not changed
        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        /// 10 ETH harvested
        strategy.harvest(0, 0, 0, address(0));
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
        vm.revertTo(beforeReportSnapshotId);

        /// Case #3: We harvest 100% of profit
        vm.expectEmit();
        // debt: 40 eth
        emit StrategyReported(
            address(strategy),
            /// vault gain - 10 ETH
            5 ether,
            /// vault gain - 10 ETH
            10 ether,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain - 10 ETH
            5 ether,
            /// strategy loss
            0,
            /// strategy total debt: not changing now
            40 ether,
            /// credit 0 ether due to transferring funds from strategy to vault
            0,
            4000
        );
        /// debtratio not changed
        vm.expectEmit();
        emit Harvested(5 ether, 0, 0, 0);
        /// 10 ETH harvested
        strategy.harvest(0, 0, 5000, address(0));
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether + 5 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        /// ⭕️ SCENARIO 2:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Emergency exit is activated
        /// 2. Strategy earns 10 ETH. Strategy performs second harvest to request more funds.
        /// Due to emergency mode, all funds are returned back to vault
        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        /// Step #1
        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// realized profit
            0,
            /// unrealized profit
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain
            0,
            /// strategy loss
            40 ether,
            /// strategy total debt
            40 ether,
            /// credit 40 ether due to transferring funds from vault to strategy
            4000
        );
        /// debtratio not changed

        expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, 0, address(0));

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertApproxEq(
            IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)),
            expectedStrategyShareBalance,
            expectedStrategyShareBalance / 100
        );

        /// Step #2
        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        /// Step #3
        vm.startPrank(users.keeper);

        /// Fake gains in strategy (10 ETH = 40 ETH transferred previously + 10 ETH gains)
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            49.970026864837587483 ether,
            /// vault gain + all of strategy's funds (40 initial ETH + 9.999999 ETH gain)
            0,
            // unrealised vault gain is 0 because we dont want to assess fees
            0,
            /// vault loss
            0,
            /// vault debtPayment
            49.970026864837587483 ether,
            /// strategy realized gain - 9.99999 ETH
            0,
            /// strategy loss
            40 ether,
            /// strategy total debt: not changing now
            0,
            /// credit 0 ether due to transferring funds from strategy to vault
            4000
        );
        /// debtratio not changed

        vm.expectEmit();
        emit Harvested(49.970026864837587483 ether, 0, 0, 0);
        /// 49.997 ETH harvested

        /// no effect since the strategy is in emergency exit
        strategy.harvest(0, 0, 2000, address(0));
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 109.970026864837587483 ether);
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy loses 10 ETH. Strategy performs second harvest and its debt ratio gets reduced
        /// Dust in `_shareBalance()` makes it compulsory to transfer 9.99 ETH to vault, instead of 10 ETH
        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// realized profit
            0,
            /// unrealized profit
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain
            0,
            /// strategy loss
            40 ether,
            /// strategy total debt
            40 ether,
            /// credit 40 ether due to transferring funds from vault to strategy
            4000
        );
        /// debtratio not changed
        expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, 0, address(0));

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertApproxEq(
            IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)),
            expectedStrategyShareBalance,
            expectedStrategyShareBalance / 100
        );

        /// 2. Strategy loses 10 ETH
        /// - Expected a 1000 reduction in debt ratio, 30% of total funds should be in the strategy
        /// - Total funds are now 90 ETH, 30% of which must be in strategy
        /// - 30% of 90 ETH = 27 ETH, but strategy still has 30 ETH -> there is a debt outstanding of 3 ETH

        /// Fake loss in strategy(shares are sent to a random address)
        uint256 expectedShares = strategy.sharesForAmount(10 ether);

        vm.startPrank(address(strategy));
        IERC20(CELLAR_STETH_MAINNET).transfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// realized profit
            0,
            /// unrealized profit
            9.994505359021543791 ether,
            /// vault loss - 9.994505359021543791 ether
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain
            9.994505359021543791 ether,
            /// strategy loss - 10 ETH
            30.005494640978456209 ether,
            /// strategy total debt: 10 ETH less than initial debt
            0,
            /// credit 0 ether due to transferring funds from strategy to vault
            3001
        );
        /// debtratio reduced

        vm.expectEmit();
        emit Harvested(0, 9.994505359021543791 ether, 0, 2.994845699220821501 ether);
        /// 10 ETH loss
        strategy.harvest(0, 0, 10_000, address(0));

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(vault.totalDebt(), 30.005494640978456209 ether);
        assertEq(data.strategyDebtRatio, 3001);
        assertEq(data.strategyTotalDebt, 30.005494640978456209 ether);
        assertEq(data.strategyTotalLoss, 9.994505359021543791 ether);
    }

    function testSommelierStEthDeposit_TurboStEth__Harvest_Negatives() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        // it should revert if profit harvest percentage is > 100 %
        vm.startPrank(users.keeper);
        vm.expectRevert(abi.encodeWithSignature("InvalidHarvestedProfit()"));
        strategy.harvest(0, 0, 10_001, address(0));
    }

    function testSommelierStEthDeposit_TurboStEth__Harvest_CellarIsShutdown_Paused() public {
        /// ⭕️ SCENARIO 1:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Cellar is shutdown/paused so it takes the fund but they are not invested in the cellar

        /// 1. When paused
        uint256 snapshotId = vm.snapshot();
        // cellar is paused
        _pauseCellar();

        /// Deposit into vault
        vm.startPrank(users.alice);
        vault.deposit(100 ether, users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// realized profit
            0,
            /// unrealized profit
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain
            0,
            /// strategy loss
            40 ether,
            /// strategy total debt
            40 ether,
            /// credit 40 ether due to transferring funds from vault to strategy
            4000
        );
        vm.stopPrank();
        /// debtratio not changed
        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, 10_000, address(0));

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        /// 2. When shutdown

        // cellar is shutdown
        _shutDownCellar();

        /// Deposit into vault
        vm.startPrank(users.alice);
        vault.deposit(100 ether, users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// realized profit
            0,
            /// unrealized profit
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain
            0,
            /// strategy loss
            40 ether,
            /// strategy total debt
            40 ether,
            /// credit 40 ether due to transferring funds from vault to strategy
            4000
        );
        vm.stopPrank();
        /// debtratio not changed
        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, 10_000, address(0));

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 2:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy earns 10 eth
        /// 3. Harvest again to report profit, it will report 0 because cellar is paused
        /// and cannot withdraw

        /// Deposit into vault
        vm.startPrank(users.alice);
        vault.deposit(100 ether, users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// realized profit
            0,
            /// unrealized profit
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain
            0,
            /// strategy loss
            40 ether,
            /// strategy total debt
            40 ether,
            /// credit 40 ether due to transferring funds from vault to strategy
            4000
        );
        vm.stopPrank();
        /// debtratio not changed
        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, 10_000, address(0));

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertGt(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });

        _pauseCellar();

        vm.expectEmit();
        // debt: 40 eth
        emit StrategyReported(
            address(strategy),
            /// vault realized gain - 0
            0,
            /// vault unrealized gain - 0
            0,
            /// vault loss 0
            0,
            /// vault debtPayment 0
            0,
            /// strategy realized gain 0
            0,
            /// strategy loss 0
            0,
            /// strategy total debt: not changing now
            40 ether,
            /// credit 0 ether due to transferring funds from strategy to vault
            0,
            4000
        );
        /// debtratio not changed
        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, 10_000, address(0));
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 10 ether);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy earns 10 eth
        /// 3. Set emergency mode
        /// 4. Cellar is paused so it reverts when trying to
        /// liquidate all the positions

        /// Deposit into vault
        vm.startPrank(users.alice);
        vault.deposit(100 ether, users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// realized profit
            0,
            /// unrealized profit
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain
            0,
            /// strategy loss
            40 ether,
            /// strategy total debt
            40 ether,
            /// credit 40 ether due to transferring funds from vault to strategy
            4000
        );
        vm.stopPrank();
        /// debtratio not changed
        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, 10_000, address(0));

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertGt(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);
    }

    /*  function testSommelierStEthDeposit_TurboStEth__Withdraw_CellarIsPaused() public {
        vm.startPrank(users.alice);
        vault.deposit(100 ether, users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// realized profit
            0,
            /// unrealized profit
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy realized gain
            0,
            /// strategy loss
            40 ether,
            /// strategy total debt
            40 ether,
            /// credit 40 ether due to transferring funds from vault to strategy
            4000
        );
        vm.stopPrank();
        /// debtratio not changed
        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, 10_000,  address(0));
        // user tries to withdraw
        vm.startPrank(users.alice);
        // cellar is paused, so strategy will only withdraw
        // his own token balance
        _pauseCellar();

        uint256 snapshotId = vm.snapshot();
        // the strategy doesnt have enough token balance to cover the
        // requested amount
        vm.expectRevert(abi.encodeWithSignature("MaxLossReached()"));
        vault.withdraw(type(uint256).max, users.alice, 10);

        vm.revertTo(snapshotId);
        // the strategy has enough idle balance
        deal({token: WETH_MAINNET, to: address(strategy), give: 50 ether});
        // make sure it withdraws 60 ether from vault + 40 ether from strategy
        assertEq(vault.withdraw(type(uint256).max, users.alice, 10), 100 ether);
    }
    */

    ////////////////////////////////////////////////////////////////
    ///                     TEST previewLiquidate()               ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 ether);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(30 ether);
        // expect the Sommelier's {previewRedeem} to be fully precise
        assertEq(expected, 30 ether - loss);
    }

    /*     function testSommelierStEthDeposit_TurboStEth__PreviewLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount >= 1e4 && amount <= 1000 ether);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(WETH_MAINNET, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0, address(0));
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(amount);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(amount);
        // expect the Sommelier's {previewRedeem} to be fully precise
        assertEq(expected, amount - loss);
    }
    */
    ////////////////////////////////////////////////////////////////
    ///                     TEST previewLiquidateExact()        ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(30 ether);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));
        strategy.liquidateExact(30 ether);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, 30 ether);
        // losses are equal or fewer than expected
        assertLe(withdrawn - 30 ether, requestedAmount - 30 ether);
    }

    /*     function testSommelierStEthDeposit_TurboStEth__PreviewLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount >= 1e4 && amount <= 1000 ether);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(WETH_MAINNET, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);       
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0, address(0));
        vm.stopPrank();                                          
        uint256 requestedAmount = strategy.previewLiquidateExact(amount);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));
        uint256 losses = strategy.liquidateExact(amount);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore ;
        // withdraw exactly what requested 
        assertEq(withdrawn, amount);
        // losses are equal or fewer than expected
        assertLe(losses , requestedAmount - amount);
    }
    */
    ////////////////////////////////////////////////////////////////
    ///                     TEST maxLiquidateExact()                    ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__maxLiquidateExact() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
        vm.stopPrank();
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    }

    /*     function testSommelierStEthDeposit_TurboStEth__maxLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount >= 1e4 && amount <= 1000 ether);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(WETH_MAINNET, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);       
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0, address(0));
        vm.stopPrank();                                                   
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore ;
        // withdraw exactly what requested 
        assertEq(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    } */

    ////////////////////////////////////////////////////////////////
    ///                     TEST maxWithdraw()                   ///
    ////////////////////////////////////////////////////////////////
    function testSommelierStEthDeposit_TurboStEth__MaxLiquidate() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
        vm.stopPrank();
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore;
        assertLe(withdrawn, maxWithdraw);
    }

    /*     function testSommelierStEthDeposit_TurboStEth__MaxLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount >= 1e4 && amount <= 1000 ether);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(WETH_MAINNET, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0, address(0));
        vm.stopPrank();                                          
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore ;
        assertLe(withdrawn, maxWithdraw);
    } */

    ////////////////////////////////////////////////////////////////
    ///                     HELPER FUNCTIONS                     ///
    ////////////////////////////////////////////////////////////////

    function _pauseCellar() internal {
        // change the value of mapping isCallerPaused(address=>bool) in the registry
        vm.store(
            0xEED68C267E9313a6ED6ee08de08c9F68dee44476,
            keccak256(abi.encode(address(CELLAR_STETH_MAINNET), uint256(6))),
            bytes32(uint256(uint8(1)))
        );
    }

    function _shutDownCellar() internal {
        // keep the other values of the slot the same
        vm.store(
            CELLAR_STETH_MAINNET,
            bytes32(uint256(6)),
            bytes32(abi.encodePacked(0x69592e6f9d21989a043646fE8225da2600e5A0f7, false, true, false, false, uint32(10)))
        );
    }
}
