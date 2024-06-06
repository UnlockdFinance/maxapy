// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import { BaseTest, IERC20, Vm, console } from "../../base/BaseTest.t.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { YearnAjnaUSDCStrategyWrapper } from "../../mock/YearnAjnaUSDCStrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { StrategyEvents } from "../../helpers/StrategyEvents.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract YearnAjnaUSDCStrategyTest is BaseTest, StrategyEvents {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////
    address public constant YVAULT_USDCE_POLYGON = 0xF54a15F6da443041Bb075959EA66EE47655DDFcA;
    address public TREASURY;

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy;
    YearnAjnaUSDCStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function setUp() public {
        super._setUp("POLYGON");
        vm.rollFork(53_869_145);

        TREASURY = makeAddr("treasury");

        /// Deploy MaxApyVault
        vaultDeployment = new MaxApyVault(USDCE_POLYGON, "MaxApyUSDCVault", "maxUSDC", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(users.alice);
        /// Deploy strategy implementation
        implementation = new YearnAjnaUSDCStrategyWrapper();

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
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                users.alice,
                YVAULT_USDCE_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(YVAULT_USDCE_POLYGON, "yVault");
        vm.label(address(proxy), "YearnAjnaUSDCStrategy");
        vm.label(address(USDCE_POLYGON), "USDC");

        strategy = IStrategyWrapper(address(_proxy));
        /// Alice approves vault for deposits
        USDCE_POLYGON.safeApprove(address(vault), type(uint256).max);
    }

    /*==================INITIALIZATION TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///                  TEST initialize()                       ///
    ////////////////////////////////////////////////////////////////

    function testYearnAjnaUSDC__Initialization() public {
        /// *************** Yearn Strategy initialization *************** ///
        /// Deploy MaxApyVault
        MaxApyVault _vault = new MaxApyVault(USDCE_POLYGON, "MaxApyUSDCVault", "maxUSDC", TREASURY);
        /// Deploy transparent upgradeable proxy admin
        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        /// Deploy strategy implementation
        YearnAjnaUSDCStrategyWrapper _implementation = new YearnAjnaUSDCStrategyWrapper();

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
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                users.alice,
                YVAULT_USDCE_POLYGON
            )
        );
        ITransparentUpgradeableProxy proxyInit = ITransparentUpgradeableProxy(address(_proxy));

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));

        /// *************** Tests *************** ///

        /// Assert vault is set to MaxApy vault deployed in setup
        assertEq(_strategy.vault(), address(_vault));
        /// Assert maxapy vault obtains `VAULT_ROLE`
        assertEq(_strategy.hasAnyRole(_strategy.vault(), _strategy.VAULT_ROLE()), true);
        /// Assert underlying asset is set to WUSDC
        assertEq(_strategy.underlyingAsset(), USDCE_POLYGON);
        /// Assert strategy has approved vault to transfer underlying
        assertEq(IERC20(USDCE_POLYGON).allowance(address(_strategy), address(_vault)), type(uint256).max);
        /// Assert keeper user has `KEEPER_ROLE` granted
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        /// Assert alice (deployer) has `ADMIN_ROLE` granted
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);
        /// Assert strategy name is correct
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy Yearn Strategy")));
        /// Assert underlying asset is set to YVAULT_USDCE_POLYGON
        assertEq(_strategy.yVault(), YVAULT_USDCE_POLYGON);
        /// Assert strategy has approved yVault to transfer underlying
        assertEq(IERC20(USDCE_POLYGON).allowance(address(_strategy), YVAULT_USDCE_POLYGON), type(uint256).max);

        /// *************** Proxy values *************** ///
        /// Assert proxy admin contract owner is set to deployer (alice)
        assertEq(_proxyAdmin.owner(), users.alice);
        /// Assert proxy admin is set to the proxy admin contract
        vm.startPrank(address(_proxyAdmin));
        // assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///                   TEST setEmergencyExit()                ///
    ////////////////////////////////////////////////////////////////

    function testYearnAjnaUSDC__SetEmergencyExit() public {
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
    ///                  TEST setMinSingleTrade()                ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaUSDC__SetMinSingleTrade() public {
        /// Test unauthorized access with a user without privileges
        vm.stopPrank();
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 * _1_USDC);

        /// Test unauthorized access with a user with `VAULT_ROLE`
        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 * _1_USDC);

        /// Test proper min single trade setting
        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit MinSingleTradeUpdated(1 * _1_USDC);
        strategy.setMinSingleTrade(1 * _1_USDC);
        assertEq(strategy.minSingleTrade(), 1 * _1_USDC);
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST isActive()                      ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaUSDC__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDCE_POLYGON, address(strategy), 1 * _1_USDC);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        (USDCE_POLYGON).safeTransfer(makeAddr("random"), IERC20(USDCE_POLYGON).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(USDCE_POLYGON, address(strategy), 1 * _1_USDC);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    ////////////////////////////////////////////////////////////////
    ///                    TEST setStrategist()                  ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaUSDC__SetStrategist() public {
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
    function testYearnAjnaUSDC__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// 1. Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _prepareReturn()                  ///
    ////////////////////////////////////////////////////////////////W
    function testYearnAjnaUSDC__PrepareReturn() public {
        /// ⭕️ SCENARIO 1:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 40 * _1_USDC
        ///     - `totalAssets` = 40 * _1_USDC
        ///     - `shares` = 0
        ///     - `debt` = 40 * _1_USDC
        /// 2. Expected outcome:
        ///     - 2.1 Strategy has obtained profit, calculate profit.
        ///     - 2.2 Profit is 0 (not gt `underlyingBalance`) -> skip divesting from yearn vault
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
        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDC, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
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
        ///            -> divest from yearn vault to obtain an extra 60 USDC
        ///     - 2.3 `amountToWithdraw` is 60 USDC, strategy holds 40 USDC already
        ///            -> `expectedAmountToWithdraw` is 20 USDC
        ///     - 2.4 Divesting causes 1 wei loss
        ///     - 2.5 `profit` >= `loss` -> profit -= loss;
        /// 3. Expected return values:
        ///     - `profit` -> around 60 USDC
        ///     - `loss` -> 0
        ///     - `debtPayment` -> 1 * _1_USDC (value passed as `debtOutstanding`)
        snapshotId = vm.snapshot();

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 60 * _1_USDC });
        /// Perform initial investment in yearn from the strategy side
        strategy.invest(60 * _1_USDC, 0);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0, TREASURY);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 59_999_999);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 59_999_998);
        assertEq(unrealizedProfit, 59_999_999);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(beforeReturnSnapshotId);
        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 29_999_999);
        assertEq(unrealizedProfit, 59_999_999);
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
        strategy.mockReport(0, 0, 0, TREASURY);

        /// Fake strategy loss of 10 USDC
        strategy.triggerLoss(10 * _1_USDC);

        beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDC);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDC);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _adjustPosition()                 ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaUSDC__AdjustPosition() public {
        /// Test if `_underlyingBalance()` is 0, no investment is performed
        strategy.adjustPosition();
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);

        /// Perform 10 USDC investment
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        /// Perform 100 USDC investment
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 100 * _1_USDC });
        expectedShares += strategy.sharesForAmount(100 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 100 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        /// Perform 500 USDC investment
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDC });
        expectedShares += strategy.sharesForAmount(500 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 500 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _invest()                         ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaUSDC__Invest() public {
        /// Test if `amount` is 0, no investment is performed
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);

        /// Test if `amount` is gt `_underlyingBalance()`, NotEnoughFundsToInvest() is thrown
        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        /// Perform 10 USDC investment
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        /// Perform 10 USDC investment
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        expectedShares += strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _divest()                         ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaUSDC__Divest() public {
        /// Perform 10 USDC investment
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        /// Divest
        uint256 strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        vm.expectEmit();
        emit Divested(address(strategy), expectedShares, 10 * _1_USDC - 1);
        uint256 amountDivested = strategy.divest(expectedShares);
        assertEq(amountDivested, 10 * _1_USDC - 1);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidatePosition()                  ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaUSDC__LiquidatePosition() public {
        /// Liquidate position where underlying balance can cover liquidation
        /// Scenario 1
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 * _1_USDC);
        assertEq(liquidatedAmount, 1 * _1_USDC);
        assertEq(loss, 0);

        /// Scenario 2
        (liquidatedAmount, loss) = strategy.liquidatePosition(10 * _1_USDC);
        assertEq(liquidatedAmount, 10 * _1_USDC);
        assertEq(loss, 0);

        /// Liquidate position where underlying balance can't cover liquidation
        /// Scenario 1
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 5 * _1_USDC });
        strategy.invest(5 * _1_USDC, 0);
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 * _1_USDC);
        assertEq(liquidatedAmount, 14_999_999);
        /// 14.99 * _1_USDC
        assertEq(loss, 1);

        /// Scenario 2
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 1000 * _1_USDC });
        strategy.invest(1000 * _1_USDC, 0);
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDC });
        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 * _1_USDC);
        assertEq(liquidatedAmount, 999_999_999);
        /// 99.99 * _1_USDC
        assertEq(loss, 1);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidateAllPositions()              ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaUSDC__LiquidateAllPositions() public {
        /// Perform 10 USDC investment
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        /// Liquidate
        uint256 strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 9_999_999);
        /// 1 wei loss divesting
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + 9_999_999);
        /// 1 wei loss divesting
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);

        /// Perform 500 USDC investment
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDC });
        expectedShares = strategy.sharesForAmount(500 * _1_USDC);
        strategy.invest(500 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        /// Liquidate
        strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 499_999_999);
        /// 1 wei loss divesting
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + 499_999_999);
        /// 1 wei loss divesting
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST harvest()                       ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaUSDC__Harvest() public {
        /// Try to harvest not being keeper
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, address(0), block.timestamp);

        /// ⭕️ SCENARIO 1:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy earns 10 USDC. Strategy performs second harvest to request more funds.
        /// Dust in `_shareBalance()` makes it compulsory to transfer 9.99 USDC to vault, instead of 10 USDC
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault gain,
            0,
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
            40 * _1_USDC,
            /// credit 40 * _1_USDC due to transferring funds from vault to strategy
            4000
        );
        /// debtratio not changed

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance);

        /// 2. Strategy takes 10 USDC profit

        /// Fake gains in strategy (10 USDC = 40 USDC transferred previously + 10 USDC gains)
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });

        /// Case #1 : we request 0% profit harvest
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            10 * _1_USDC,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain - 0 USDC
            uint128(10 * _1_USDC),
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
        emit Harvested(10 * _1_USDC, 0, 0, 0);
        /// dont report any profit
        strategy.harvest(0, 0, address(0), block.timestamp);
        /// vault balance doesnt increase at all
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        /// the strategy reinvests all the profit
        uint256 shares = strategy.sharesForAmount(10 * _1_USDC);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance + shares, "1");

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
            /// vault gain,
            0,
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

        strategy.harvest(0, 0, address(0), block.timestamp);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance, "3");

        /// Step #2
        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        /// Step #3
        vm.startPrank(users.keeper);

        /// Fake gains in strategy (10 USDC = 40 USDC transferred previously + 10 USDC gains)
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault gain - all of strategy's funds (40 initial USD + 9.999999 USD gain)
            0,
            /// vault gain - all of strategy's funds (40 initial USD + 9.999999 USD gain)
            0,
            /// vault loss
            40 * _1_USDC,
            /// vault debtPayment
            uint128(0),
            /// strategy gain - 9.99999 USD
            0,
            /// strategy loss
            0,
            /// strategy total debt: not changing now
            0,
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            4000
        );
        /// debtratio not changed

        vm.expectEmit();
        emit Harvested(0, 0, 49_999_999, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 109_999_999);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);

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
            /// vault gain,
            0,
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
        strategy.harvest(0, 0, address(0), block.timestamp);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance, "4");

        /// 2. Strategy loses 10 USDC
        /// - Expected a 1000 reduction in debt ratio, 30% of total funds should be in the strategy
        /// - Total funds are now 90 USDC, 30% of which must be in strategy
        /// - 30% of 90 USDC = 27 USDC, but strategy still has 30 USDC -> there is a debt outstanding of 3 USDC
        /// Fake loss in strategy
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);

        vm.startPrank(address(strategy));
        (YVAULT_USDCE_POLYGON).safeTransfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault gain,
            0,
            10 * _1_USDC,
            /// vault loss - 9.999999 USDC
            0,
            /// vault debtPayment
            0,
            /// strategy gain
            uint128(10 * _1_USDC),
            /// strategy loss - 10 USDC
            uint128(30 * _1_USDC),
            /// strategy total debt: 10 USDC less than initial debt
            0,
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            3000
        );
        /// debtratio reduced

        vm.expectEmit();
        emit Harvested(0, 10 * _1_USDC, 0, 3 * _1_USDC);
        /// 10 USDC loss
        /// if we request to harvest only 30% of profit it wont have any effect neither,
        /// since the strategy has loses only
        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(vault.totalDebt(), 30 * _1_USDC);
        assertEq(data.strategyDebtRatio, 3000);
        assertEq(data.strategyTotalDebt, 30 * _1_USDC);
        assertEq(data.strategyTotalLoss, 10 * _1_USDC);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault gain,
            0,
            1,
            /// vault loss - 1 wei. This is due to the fact that strategy had to withdraw 3 USDC from yearn (totalDebt
            /// should be 27 USDC but was 30 USDC), causing 1 wei loss
            2_999_999,
            /// vault debtPayment (3 USDC - 1 wei loss)
            0,
            /// strategy gain
            uint128(10 * _1_USDC + 1),
            /// strategy loss - 10 USDC previously lost + 1 wei loss
            uint128(27 * _1_USDC),
            /// strategy total debt: 27 USDC, back to regular values
            0,
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            3000
        );
        /// debtratio: 30% of funds shared with strategy

        vm.expectEmit();
        emit Harvested(0, 1 wei, 2_999_999, 1);
        /// 10 USDC loss

        uint256 vaultBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        uint256 strategyBalanceBefore = IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy));
        uint256 expectedShareDecrease = strategy.sharesForAmount(2_999_999);

        strategy.harvest(0, 0, address(0), block.timestamp);

        data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(vault.totalDebt(), 27 * _1_USDC);
        assertEq(data.strategyDebtRatio, 3000);
        assertEq(data.strategyTotalDebt, 27 * _1_USDC);
        assertEq(data.strategyTotalLoss, 10 * _1_USDC + 1);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), vaultBalanceBefore + 2_999_999);
        assertLe(
            IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore - expectedShareDecrease
        );
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST previewLiquidate()               ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaUSDC__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 * _1_USDC);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(30 * _1_USDC);
        // expect the Sommelier's {previewRedeem} to be fully precise
        assertEq(expected, 30 * _1_USDC - loss);
    }

    /* function testYearnAjnaUSDC__PreviewLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount > 1e4 && amount <= 1000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDCE_POLYGON, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0, address(0));
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(amount);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(amount);
        // expect the Sommelier's {previewRedeem} to be fully precise
        assertEq(expected, amount - loss);
    } */

    ////////////////////////////////////////////////////////////////
    ///                     TEST previewLiquidateExact()        ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaUSDC__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(30 * _1_USDC);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        strategy.liquidateExact(30 * _1_USDC);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, 30 * _1_USDC);
        // losses are equal or fewer than expected
        assertLe(withdrawn - 30 * _1_USDC, requestedAmount - 30 * _1_USDC);
    }

    /*  function testYearnAjnaUSDC__PreviewLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount > 1e4 && amount <= 1000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDCE_POLYGON, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);       
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0, address(0));
        vm.stopPrank();                                          
        uint256 requestedAmount = strategy.previewLiquidateExact(amount);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        uint256 losses = strategy.liquidateExact(amount);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore ;
        // withdraw exactly what requested 
        assertEq(withdrawn, amount);
        // losses are equal or fewer than expected
        assertLe(losses , requestedAmount - amount);
    } */

    ////////////////////////////////////////////////////////////////
    ///                     TEST maxLiquidateExact()                    ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaUSDC__maxLiquidateExact() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    }

    /*  function testYearnAjnaUSDC__maxLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount > 1e4 && amount <= 1000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDCE_POLYGON, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);       
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0, address(0));
        vm.stopPrank();                                                   
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore ;
        // withdraw exactly what requested 
        assertEq(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    } */

    ////////////////////////////////////////////////////////////////
    ///                     TEST maxWithdraw()                   ///
    ////////////////////////////////////////////////////////////////

    function testYearnAjnaUSDC__MaxLiquidate() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
        assertLe(withdrawn, maxWithdraw);
    }

    /*   function testYearnAjnaUSDC__MaxLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount > 1e4 && amount <= 1000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDCE_POLYGON, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0, address(0));
        vm.stopPrank();                                          
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore ;
        assertLe(withdrawn, maxWithdraw);
    } */
}
