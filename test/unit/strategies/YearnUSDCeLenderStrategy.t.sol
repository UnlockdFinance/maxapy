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
import {YearnUSDCeLenderStrategyWrapper} from "../../mock/YearnUSDCeLenderStrategyWrapper.sol";
import {MaxApyVaultV2} from "src/MaxApyVaultV2.sol";
import {StrategyData} from "src/helpers/VaultTypes.sol";
import {StrategyEvents} from "../../helpers/StrategyEvents.sol";

contract YearnUSDCeLenderStrategyTest is BaseTest, StrategyEvents {
    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////
    address public constant YVAULT_USDCE_POLYGON = 0xdB92B89Ca415c0dab40Dc96E99Fc411C08F20780;
    address public TREASURY;

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy;
    YearnUSDCeLenderStrategyWrapper public implementation;
    MaxApyVaultV2 public vaultDeployment;
    IMaxApyVaultV2 public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function setUp() public {
        super._setUp("POLYGON");
        vm.rollFork(53869145);

        TREASURY = makeAddr("treasury");

        /// Deploy MaxApyVaultV2
        vaultDeployment = new MaxApyVaultV2(USDCE_POLYGON, "MaxApyUSDCEVault", "maxUSDCE", TREASURY);

        vault = IMaxApyVaultV2(address(vaultDeployment));
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin();
        /// Deploy strategy implementation
        implementation = new YearnUSDCeLenderStrategyWrapper();

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
        vm.label(address(proxy), "YearnUSDCeLenderStrategy");
        vm.label(address(USDCE_POLYGON), "USDCe");

        strategy = IStrategyWrapper(address(_proxy));

        /// Alice approves vault for deposits
        IERC20(USDCE_POLYGON).approve(address(vault), type(uint256).max);
    }

    /*==================INITIALIZATION TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///                  TEST initialize()                       ///
    ////////////////////////////////////////////////////////////////

    function testYearnUSDCeLender__Initialization() public {
        /// *************** Yearn Strategy initialization *************** ///
        /// Deploy MaxApyVaultV2
        MaxApyVaultV2 _vault = new MaxApyVaultV2(USDCE_POLYGON, "MaxApyUSDCEVault", "maxUSDCE", TREASURY);
        /// Deploy transparent upgradeable proxy admin
        ProxyAdmin _proxyAdmin = new ProxyAdmin();
        /// Deploy strategy implementation
        YearnUSDCeLenderStrategyWrapper _implementation = new YearnUSDCeLenderStrategyWrapper();

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
        /// Assert underlying asset is set to WETH
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
        assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///                   TEST setEmergencyExit()                ///
    ////////////////////////////////////////////////////////////////

    function testYearnUSDCeLender__SetEmergencyExit() public {
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
    function testYearnUSDCeLender__SetMinSingleTrade() public {
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
    function testYearnUSDCeLender__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDCE_POLYGON, address(strategy), 1 * _1_USDC);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(USDCE_POLYGON).transfer(makeAddr("random"), IERC20(USDCE_POLYGON).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(USDCE_POLYGON, address(strategy), 1 * _1_USDC);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
        assertEq(strategy.isActive(), true);
    }

    ////////////////////////////////////////////////////////////////
    ///                    TEST setStrategist()                  ///
    ////////////////////////////////////////////////////////////////
    function testYearnUSDCeLender__SetStrategist() public {
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
    function testYearnUSDCeLender__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// 1. Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, 10_000, address(0));
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _prepareReturn()                  ///
    ////////////////////////////////////////////////////////////////W
    function testYearnUSDCeLender__PrepareReturn() public {
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

        (uint256 realizedProfit, uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) =
            strategy.prepareReturn(1 * _1_USDC, 0, 5000);
        assertEq(realizedProfit, 0);
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
        ///     - 2.2 Profit is around 60 ETH (it is greater than `underlyingBalance`)
        ///            -> divest from yearn vault to obtain an extra 60 ETH
        ///     - 2.3 `amountToWithdraw` is 60 ETH, strategy holds 40 ETH already
        ///            -> `expectedAmountToWithdraw` is 20 ETH
        ///     - 2.4 Divesting causes 1 wei loss
        ///     - 2.5 `profit` >= `loss` -> profit -= loss;
        /// 3. Expected return values:
        ///     - `profit` -> around 60 ETH
        ///     - `loss` -> 0
        ///     - `debtPayment` -> 1 * _1_USDC (value passed as `debtOutstanding`)
        snapshotId = vm.snapshot();

        deal({token: USDCE_POLYGON, to: address(strategy), give: 60 * _1_USDC});
        /// Perform initial investment in yearn from the strategy side
        strategy.invest(60 * _1_USDC, 0);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0, TREASURY);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 0);
        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 59999999);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 10_000);

        assertEq(realizedProfit, 59999998);
        assertEq(unrealizedProfit, 59999999);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(beforeReturnSnapshotId);
        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 5000);

        assertEq(realizedProfit, 29999999);
        assertEq(unrealizedProfit, 59999999);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 30 * _1_USDC (10 ETH lost)
        ///     - `totalAssets` = 30 * _1_USDC
        ///     - `shares` = 0
        ///     - `debt` = 40 * _1_USDC
        /// 2. Expected outcome:
        ///     - 2.1 Strategy has incurred a loss
        ///     - 2.2 Calculate loss with `debt - totalAssets` (40 ETH - 30 ETH = 10 ETH)
        snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0, TREASURY);

        /// Fake strategy loss of 10 ETH
        strategy.triggerLoss(10 * _1_USDC);

        beforeReturnSnapshotId = vm.snapshot();

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 0);
        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDC);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 10_000);
        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDC);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _adjustPosition()                 ///
    ////////////////////////////////////////////////////////////////
    function testYearnUSDCeLender__AdjustPosition() public {
        /// Test if `_underlyingBalance()` is 0, no investment is performed
        strategy.adjustPosition();
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);

        /// Perform 10 ETH investment
        deal({token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC});
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        /// Perform 100 ETH investment
        deal({token: USDCE_POLYGON, to: address(strategy), give: 100 * _1_USDC});
        expectedShares += strategy.sharesForAmount(100 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 100 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        /// Perform 500 ETH investment
        deal({token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDC});
        expectedShares += strategy.sharesForAmount(500 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 500 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _invest()                         ///
    ////////////////////////////////////////////////////////////////
    function testYearnUSDCeLender__Invest() public {
        /// Test if `amount` is 0, no investment is performed
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);

        /// Test if `amount` is gt `_underlyingBalance()`, NotEnoughFundsToInvest() is thrown
        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        /// Perform 10 ETH investment
        deal({token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC});
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        /// Perform 10 ETH investment
        deal({token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC});
        expectedShares += strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _divest()                         ///
    ////////////////////////////////////////////////////////////////
    function testYearnUSDCeLender__Divest() public {
        /// Perform 10 ETH investment
        deal({token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC});
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
    function testYearnUSDCeLender__LiquidatePosition() public {
        /// Liquidate position where underlying balance can cover liquidation
        /// Scenario 1
        deal({token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC});
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 * _1_USDC);
        assertEq(liquidatedAmount, 1 * _1_USDC);
        assertEq(loss, 0);

        /// Scenario 2
        (liquidatedAmount, loss) = strategy.liquidatePosition(10 * _1_USDC);
        assertEq(liquidatedAmount, 10 * _1_USDC);
        assertEq(loss, 0);

        /// Liquidate position where underlying balance can't cover liquidation
        /// Scenario 1
        deal({token: USDCE_POLYGON, to: address(strategy), give: 5 * _1_USDC});
        strategy.invest(5 * _1_USDC, 0);
        deal({token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC});
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 * _1_USDC);
        assertEq(liquidatedAmount, 14999999);
        /// 14.99 * _1_USDC
        assertEq(loss, 1);

        /// Scenario 2
        deal({token: USDCE_POLYGON, to: address(strategy), give: 1000 * _1_USDC});
        strategy.invest(1000 * _1_USDC, 0);
        deal({token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDC});
        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 * _1_USDC);
        assertEq(liquidatedAmount, 999999999);
        /// 99.99 * _1_USDC
        assertEq(loss, 1);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidateAllPositions()              ///
    ////////////////////////////////////////////////////////////////
    function testYearnUSDCeLender__LiquidateAllPositions() public {
        /// Perform 10 ETH investment
        deal({token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC});
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        /// Liquidate
        uint256 strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 9999999);
        /// 1 wei loss divesting
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + 9999999);
        /// 1 wei loss divesting
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);

        /// Perform 500 ETH investment
        deal({token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDC});
        expectedShares = strategy.sharesForAmount(500 * _1_USDC);
        strategy.invest(500 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        /// Liquidate
        strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 499999999);
        /// 1 wei loss divesting
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + 499999999);
        /// 1 wei loss divesting
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST harvest()                       ///
    ////////////////////////////////////////////////////////////////
    function testYearnUSDCeLender__Harvest_Negatives() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        // it should revert if profit harvest percentage is > 100 %
        vm.startPrank(users.keeper);
        vm.expectRevert(abi.encodeWithSignature("InvalidHarvestedProfit()"));
        strategy.harvest(0, 0, 10_001, address(0));
    }

    function testYearnUSDCeLender__Harvest() public {
        /// Try to harvest not being keeper
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, 10_000, address(0));

        /// ⭕️ SCENARIO 1:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy earns 10 ETH. Strategy performs second harvest to request more funds.
        /// Dust in `_shareBalance()` makes it compulsory to transfer 9.99 ETH to vault, instead of 10 ETH
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
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
        strategy.harvest(0, 0, 10_000, address(0));

        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance);

        /// 2. Strategy takes 10 ETH profit

        /// Fake gains in strategy (10 ETH = 40 ETH transferred previously + 10 ETH gains)
        deal({token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC});
        uint256 beforeReportSnapshotId = vm.snapshot();

        /// Case #1 : we request 0% profit harvest
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault gain - 0 ETH
            0,
            10 * _1_USDC,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain - 0 ETH
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
        /// dont report any profit
        strategy.harvest(0, 0, 0, address(0));
        /// vault balance doesnt increase at all
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        /// the strategy reinvests all the profit
        uint256 shares = strategy.sharesForAmount(10 * _1_USDC);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance + shares, "1");

        vm.revertTo(beforeReportSnapshotId);

        /// Case #2 : we request 45,23% profit harvest
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault gain ~ 10 ETH * 45.23%
            uint128(4523000),
            /// vault gain ~ 10 ETH * 45.23%
            10 * _1_USDC,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain ~ 10 ETH * 45.23%
            uint128(4523000),
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
        emit Harvested(4523000, 0, 0, 0);
        /// dont report any profit
        strategy.harvest(0, 0, 4523, address(0));
        /// vault balance doesnt increase at all                    // 4.52 * _1_USDC
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC + 4523000);
        /// the strategy reinvests the profit partially          // 5.477 * _1_USDC
        shares = strategy.sharesForAmount(5477000);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance + shares, "2");

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
        vault.deposit(100 * _1_USDC, users.alice);

        /// Step #1
        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
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

        strategy.harvest(0, 0, 0, address(0));

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance, "3");

        /// Step #2
        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        /// Step #3
        vm.startPrank(users.keeper);

        /// Fake gains in strategy (10 ETH = 40 ETH transferred previously + 10 ETH gains)
        deal({token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC});

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            49999999,
            /// vault gain - all of strategy's funds (40 initial ETH + 9.999999 ETH gain)
            0,
            /// vault gain - all of strategy's funds (40 initial ETH + 9.999999 ETH gain)
            0,
            /// vault loss
            0,
            /// vault debtPayment
            uint128(49999999),
            /// strategy gain - 9.99999 ETH
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

        /// only harvest 50% of profit, but it wont have any effect since its an emergency exit
        strategy.harvest(0, 0, 5000, address(0));
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 109999999);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy loses 10 ETH. Strategy performs second harvest and its debt ratio gets reduced
        /// Dust in `_shareBalance()` makes it compulsory to transfer 9.99 ETH to vault, instead of 10 ETH
        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
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
        strategy.harvest(0, 0, 10_000, address(0));

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance, "4");

        /// 2. Strategy loses 10 ETH
        /// - Expected a 1000 reduction in debt ratio, 30% of total funds should be in the strategy
        /// - Total funds are now 90 ETH, 30% of which must be in strategy
        /// - 30% of 90 ETH = 27 ETH, but strategy still has 30 ETH -> there is a debt outstanding of 3 ETH
        /// Fake loss in strategy
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);

        vm.startPrank(address(strategy));
        IERC20(YVAULT_USDCE_POLYGON).transfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// vault gain,
            0,
            10 * _1_USDC,
            /// vault loss - 10 * _1_USDC
            0,
            /// vault debtPayment
            0,
            /// strategy gain
            uint128(10 * _1_USDC),
            /// strategy loss - 10 ETH
            uint128(30 * _1_USDC),
            /// strategy total debt: 10 ETH less than initial debt
            0,
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            3000
        );
        /// debtratio reduced

        vm.expectEmit();
        emit Harvested(0, 10 * _1_USDC, 0, 3 * _1_USDC);
        /// 10 ETH loss
        /// if we request to harvest only 30% of profit it wont have any effect neither,
        /// since the strategy has loses only
        strategy.harvest(0, 0, 3_000, address(0));

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(vault.totalDebt(), 30 * _1_USDC);
        assertEq(data.strategyDebtRatio, 3000);
        assertEq(data.strategyTotalDebt, 30 * _1_USDC);
        assertEq(data.strategyTotalLoss, 10 * _1_USDC);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// vault gain,
            0,
            1,
            /// vault loss - 1 wei. This is due to the fact that strategy had to withdraw 3 ETH from yearn (totalDebt should be 27 ETH but was 30 ETH), causing 1 wei loss
            2999999,
            /// vault debtPayment (3 ETH - 1 wei loss)
            0,
            /// strategy gain
            uint128(10 * _1_USDC + 1),
            /// strategy loss - 10 ETH previously lost + 1 wei loss
            uint128(27 * _1_USDC),
            /// strategy total debt: 27 ETH, back to regular values
            0,
            /// credit 0 * _1_USDC due to transferring funds from strategy to vault
            3000
        );
        /// debtratio: 30% of funds shared with strategy

        vm.expectEmit();
        emit Harvested(0, 1 wei, 2999999, 1);
        /// 10 ETH loss

        uint256 vaultBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        uint256 strategyBalanceBefore = IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy));
        uint256 expectedShareDecrease = strategy.sharesForAmount(2999999);
        // here requesting 20% wont have any effect neither
        strategy.harvest(0, 0, 2000, address(0));

        data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(vault.totalDebt(), 27 * _1_USDC);
        assertEq(data.strategyDebtRatio, 3000);
        assertEq(data.strategyTotalDebt, 27 * _1_USDC);
        assertEq(data.strategyTotalLoss, 10 * _1_USDC + 1);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), vaultBalanceBefore + 2999999);
        assertLe(
            IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore - expectedShareDecrease
        );
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST previewLiquidate()               ///
    ////////////////////////////////////////////////////////////////
    function testYearnUSDCeLender__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 * _1_USDC);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(30 * _1_USDC);
        // expect the Sommelier's {previewRedeem} to be fully precise
        assertEq(expected, 30 * _1_USDC - loss);
    }

  /*   function testYearnUSDCeLender__PreviewLiquidate__FUZZY(uint256 amount) public {
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
    function testYearnUSDCeLender__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
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

  /*   function testYearnUSDCeLender__PreviewLiquidateExact__FUZZY(uint256 amount) public {
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
    function testYearnUSDCeLender__maxLiquidateExact() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
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
    
   /*  function testYearnUSDCeLender__maxLiquidateExact__FUZZY(uint256 amount) public {
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

    function testYearnUSDCeLender__MaxLiquidate() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
        vm.stopPrank();
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
        assertLe(withdrawn, maxWithdraw);
    }

  /*   function testYearnUSDCeLender__MaxLiquidate__FUZZY(uint256 amount) public {
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
