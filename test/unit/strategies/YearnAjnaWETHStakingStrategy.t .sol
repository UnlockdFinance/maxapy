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
import {YearnAjnaWETHStakingStrategyWrapper} from "../../mock/YearnAjnaWETHStakingStrategyWrapper.sol";
import {MaxApyVaultV2} from "src/MaxApyVaultV2.sol";
import {StrategyData} from "src/helpers/VaultTypes.sol";
import {StrategyEvents} from "../../helpers/StrategyEvents.sol";

contract YearnAjnaWETHStakingStrategyTest is BaseTest, StrategyEvents {
    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////
    address public constant YVAULT_WETH_MAINNET = 0x503e0BaB6acDAE73eA7fb7cf6Ae5792014dbe935;
    address public TREASURY;

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy;
    YearnAjnaWETHStakingStrategyWrapper public implementation;
    MaxApyVaultV2 public vaultDeployment;
    IMaxApyVaultV2 public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;
    address stakingRewards;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function setUp() public {
        super._setUp("MAINNET");
        vm.rollFork(19286475);

        TREASURY = makeAddr("treasury");

        /// Deploy MaxApyVaultV2
        vaultDeployment = new MaxApyVaultV2(WETH_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);

        vault = IMaxApyVaultV2(address(vaultDeployment));
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin();
        /// Deploy strategy implementation
        implementation = new YearnAjnaWETHStakingStrategyWrapper();

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
                YVAULT_WETH_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(YVAULT_WETH_MAINNET, "yVault");
        vm.label(address(proxy), "YearnAjnaWETHStakingStrategy");
        vm.label(address(WETH_MAINNET), "WETH");
        vm.label(stakingRewards = address(implementation.yearnStakingRewards()), "YearnStakingRewardsMulti");
        vm.label(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079, "AJNA");

        strategy = IStrategyWrapper(address(_proxy));

        /// Alice approves vault for deposits
        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
    }

    /*==================INITIALIZATION TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///                  TEST initialize()                       ///
    ////////////////////////////////////////////////////////////////

    function testYearnAjnaWETH_Staking__Initialization() public {
        /// *************** Yearn Strategy initialization *************** ///
        /// Deploy MaxApyVaultV2
        MaxApyVaultV2 _vault = new MaxApyVaultV2(WETH_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);
        /// Deploy transparent upgradeable proxy admin
        ProxyAdmin _proxyAdmin = new ProxyAdmin();
        /// Deploy strategy implementation
        YearnAjnaWETHStakingStrategyWrapper _implementation = new YearnAjnaWETHStakingStrategyWrapper();

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
                YVAULT_WETH_MAINNET
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
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy Yearn Strategy")));
        /// Assert underlying asset is set to YVAULT_WETH_MAINNET
        assertEq(_strategy.yVault(), YVAULT_WETH_MAINNET);
        /// Assert strategy has approved yVault to transfer underlying
        assertEq(IERC20(WETH_MAINNET).allowance(address(_strategy), YVAULT_WETH_MAINNET), type(uint256).max);

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
    function testYearnAjnaWETH_Staking__SetEmergencyExit() public {
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
    ///                  TEST setMaxSingleTrade()                ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__SetMaxSingleTrade() public {
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
    function testYearnAjnaWETH_Staking__SetMinSingleTrade() public {
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
    ///                     TEST isActive()                      ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(IERC20(stakingRewards).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(WETH_MAINNET).transfer(makeAddr("random"), IERC20(WETH_MAINNET).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0));
        assertEq(strategy.isActive(), true);
    }

    ////////////////////////////////////////////////////////////////
    ///                    TEST setStrategist()                  ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__SetStrategist() public {
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
    function testYearnAjnaWETH_Staking__InvestmentSlippage() public {
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
    ////////////////////////////////////////////////////////////////W
    function testYearnAjnaWETH_Staking__PrepareReturn() public {
        /// ⭕️ SCENARIO 1:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 40 ether
        ///     - `totalAssets` = 40 ether
        ///     - `shares` = 0
        ///     - `debt` = 40 ether
        /// 2. Expected outcome:
        ///     - 2.1 Strategy has obtained profit, calculate profit.
        ///     - 2.2 Profit is 0 (not gt `underlyingBalance`) -> skip divesting from yearn vault
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
        ///            -> divest from yearn vault to obtain an extra 60 ETH
        ///     - 2.3 `amountToWithdraw` is 60 ETH, strategy holds 40 ETH already
        ///            -> `expectedAmountToWithdraw` is 20 ETH
        ///     - 2.4 Divesting causes 1 wei loss
        ///     - 2.5 `profit` >= `loss` -> profit -= loss;
        /// 3. Expected return values:
        ///     - `profit` -> around 60 ETH
        ///     - `loss` -> 0
        ///     - `debtPayment` -> 1 ether (value passed as `debtOutstanding`)
        snapshotId = vm.snapshot();

        deal({token: WETH_MAINNET, to: address(strategy), give: 60 ether});
        /// Perform initial investment in yearn from the strategy side
        strategy.invest(60 ether, 0);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0, TREASURY);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 0);
        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 60 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 10_000);
        assertEq(realizedProfit, 60 ether);
        assertEq(unrealizedProfit, 60 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(beforeReturnSnapshotId);
        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 5000);

        assertEq(realizedProfit, 30 ether);
        assertEq(unrealizedProfit, 60 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

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

        beforeReturnSnapshotId = vm.snapshot();

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 0);
        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 ether);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 10_000);
        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 ether);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _adjustPosition()                 ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__AdjustPosition() public {
        /// Test if `_underlyingBalance()` is 0, no investment is performed
        strategy.adjustPosition();
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), 0);

        /// Perform 10 ETH investment
        deal({token: WETH_MAINNET, to: address(strategy), give: 10 ether});
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));

        /// Perform 100 ETH investment
        deal({token: WETH_MAINNET, to: address(strategy), give: 100 ether});
        expectedShares += strategy.sharesForAmount(100 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 100 ether);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));

        /// Perform 500 ETH investment
        deal({token: WETH_MAINNET, to: address(strategy), give: 500 ether});
        expectedShares += strategy.sharesForAmount(500 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 500 ether);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _invest()                         ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__Invest() public {
        /// Test if `amount` is 0, no investment is performed
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), 0);

        /// Test if `amount` is gt `_underlyingBalance()`, NotEnoughFundsToInvest() is thrown
        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        /// Perform 10 ETH investment
        deal({token: WETH_MAINNET, to: address(strategy), give: 10 ether});
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));

        /// Perform 10 ETH investment
        deal({token: WETH_MAINNET, to: address(strategy), give: 10 ether});
        expectedShares += strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _divest()                         ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__Divest() public {
        /// Perform 10 ETH investment
        deal({token: WETH_MAINNET, to: address(strategy), give: 10 ether});
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        strategy.invest(10 ether, 0);
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));

        /// Divest
        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        vm.expectEmit();
        emit Divested(address(strategy), expectedShares, 10 ether);
        uint256 amountDivested = strategy.divest(expectedShares);
        assertEq(amountDivested, 10 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidatePosition()                  ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__LiquidatePosition() public {
        /// Liquidate position where underlying balance can cover liquidation
        /// Scenario 1
        deal({token: WETH_MAINNET, to: address(strategy), give: 10 ether});
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 ether);
        assertEq(liquidatedAmount, 1 ether);
        assertEq(loss, 0);

        /// Scenario 2
        (liquidatedAmount, loss) = strategy.liquidatePosition(10 ether);
        assertEq(liquidatedAmount, 10 ether);
        assertEq(loss, 0);

        /// Liquidate position where underlying balance can't cover liquidation
        /// Scenario 1
        deal({token: WETH_MAINNET, to: address(strategy), give: 5 ether});
        strategy.invest(5 ether, 0);
        deal({token: WETH_MAINNET, to: address(strategy), give: 10 ether});
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 ether);
        /// 15 ether
        assertEq(liquidatedAmount, 15 ether);
        assertEq(loss, 0);

        /// Scenario 2
        deal({token: WETH_MAINNET, to: address(strategy), give: 1000 ether});
        strategy.invest(1000 ether, 0);
        deal({token: WETH_MAINNET, to: address(strategy), give: 500 ether});
        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 ether);
        /// 1000 ether
        assertEq(liquidatedAmount, 1000 ether);
        assertEq(loss, 0);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidateAllPositions()              ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__LiquidateAllPositions() public {
        /// Perform 10 ETH investment
        deal({token: WETH_MAINNET, to: address(strategy), give: 10 ether});
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        strategy.invest(10 ether, 0);
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));

        /// Liquidate
        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 10 ether);
        /// no loss from divesting
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + 10 ether);
        /// no loss from divesting
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), 0);

        /// Perform 500 ETH investment
        deal({token: WETH_MAINNET, to: address(strategy), give: 500 ether});
        expectedShares = strategy.sharesForAmount(500 ether);
        strategy.invest(500 ether, 0);
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));

        /// Liquidate
        strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 500 ether);
        /// no loss from divesting
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + 500 ether);
        /// no loss from divesting
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _unwindRewards()                  ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__UnwindRewards() public {
        /// Perform 10 ETH investment without rewards
        deal({token: WETH_MAINNET, to: address(strategy), give: 1000 ether});
        vm.expectEmit();
        emit Invested(address(strategy), 1000 ether);
        strategy.invest(1000 ether, 0);

        strategy.unwindRewards();
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);

        /// Expect rewards in AJNA
        vm.warp(block.timestamp + 10 days);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
        strategy.unwindRewards();
        assertEq(IERC20(implementation.ajna()).balanceOf(address(strategy)), 0);
        assertGt(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST harvest()                       ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__Harvest_Negatives() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        // it should revert if profit harvest percentage is > 100 %
        vm.startPrank(users.keeper);
        vm.expectRevert(abi.encodeWithSignature("InvalidHarvestedProfit()"));
        strategy.harvest(0, 0, 10_001, address(0));
    }

    function testYearnAjnaWETH_Staking__Harvest() public {
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
        vault.deposit(100 ether, users.alice);

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
            40 ether,
            /// strategy total debt
            40 ether,
            /// credit 40 ether due to transferring funds from vault to strategy
            4000
        );
        /// debtratio not changed

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, 10_000, address(0));

        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), expectedStrategyShareBalance);

        /// 2. Strategy takes 10 ETH profit

        /// Fake gains in strategy (10 ETH = 40 ETH transferred previously + 10 ETH gains)
        deal({token: WETH_MAINNET, to: address(strategy), give: 10 ether});
        uint256 beforeReportSnapshotId = vm.snapshot();

        /// Case #1 : we request 0% profit harvest
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault gain - 0 ETH
            0,
            10 ether,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain - 0 ETH
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
        /// dont report any profit
        strategy.harvest(0, 0, 0, address(0));
        /// vault balance doesnt increase at all
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        /// the strategy reinvests all the profit
        uint256 shares = strategy.sharesForAmount(10 ether);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), expectedStrategyShareBalance + shares);

        vm.revertTo(beforeReportSnapshotId);

        /// Case #2 : we request 45,23% profit harvest
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault gain ~ 10 ETH * 45.23%
            4.523 ether,
            /// vault gain ~ 10 ETH * 45.23%
            10 ether,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain ~ 10 ETH * 45.23%
            4.523 ether,
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
        emit Harvested(4.523 ether, 0, 0, 0);
        /// dont report any profit
        strategy.harvest(0, 0, 4523, address(0));
        /// vault balance doesnt increase at all                    // 4.52 ether
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether + 4.523 ether);
        /// the strategy reinvests the profit partially          // 5.477 ether
        shares = strategy.sharesForAmount(5.477 ether);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), expectedStrategyShareBalance + shares);

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
            40 ether,
            /// strategy total debt
            40 ether,
            /// credit 40 ether due to transferring funds from vault to strategy
            4000
        );
        /// debtratio not changed

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, 0, address(0));

        expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), expectedStrategyShareBalance);

        /// Step #2
        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        /// Step #3
        vm.startPrank(users.keeper);

        /// Fake gains in strategy (10 ETH = 40 ETH transferred previously + 10 ETH gains)
        deal({token: WETH_MAINNET, to: address(strategy), give: 10 ether});

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            50 ether,
            /// vault gain - all of strategy's funds (40 initial ETH + 9.999999 ETH gain)
            0,
            /// vault gain - all of strategy's funds (40 initial ETH + 9.999999 ETH gain)
            0,
            /// vault loss
            0,
            /// vault debtPayment
            50 ether,
            /// strategy gain - 9.99999 ETH
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
        emit Harvested(50 ether, 0, 0, 0);

        /// only harvest 50% of profit, but it wont have any effect since its an emergency exit
        strategy.harvest(0, 0, 5000, address(0));
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 110 ether);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), 0);

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
            40 ether,
            /// strategy total debt
            40 ether,
            /// credit 40 ether due to transferring funds from vault to strategy
            4000
        );
        /// debtratio not changed

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, 10_000, address(0));

        expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), expectedStrategyShareBalance);

        /// 2. Strategy loses 10 ETH
        /// - Expected a 1000 reduction in debt ratio, 30% of total funds should be in the strategy
        /// - Total funds are now 90 ETH, 30% of which must be in strategy
        /// - 30% of 90 ETH = 27 ETH, but strategy still has 30 ETH -> there is a debt outstanding of 3 ETH
        /// Fake loss in strategy
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        strategy.divest(expectedShares);
        vm.startPrank(address(strategy));
        IERC20(WETH_MAINNET).transfer(makeAddr("random"), 10 ether);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// vault gain,
            0,
            10 ether,
            /// vault loss - 10 ether
            0,
            /// vault debtPayment
            0,
            /// strategy gain
            10 ether,
            /// strategy loss - 10 ETH
            30 ether,
            /// strategy total debt: 10 ETH less than initial debt
            0,
            /// credit 0 ether due to transferring funds from strategy to vault
            3000
        );
        /// debtratio reduced

        vm.expectEmit();
        emit Harvested(0, 10 ether, 0, 3 ether);
        /// 10 ETH loss
        /// if we request to harvest only 30% of profit it wont have any effect neither,
        /// since the strategy has loses only
        strategy.harvest(0, 0, 3_000, address(0));

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(vault.totalDebt(), 30 ether);
        assertEq(data.strategyDebtRatio, 3000);
        assertEq(data.strategyTotalDebt, 30 ether);
        assertEq(data.strategyTotalLoss, 10 ether);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// vault gain,
            0,
            0,
            /// vault loss - 1 wei. This is due to the fact that strategy had to withdraw 3 ETH from yearn (totalDebt should be 27 ETH but was 30 ETH), causing 1 wei loss
            3 ether,
            /// vault debtPayment (3 ETH - 1 wei loss)
            0,
            /// strategy gain
            10 ether,
            /// strategy loss - 10 ETH previously lost + 1 wei loss
            27 ether,
            /// strategy total debt: 27 ETH, back to regular values
            0,
            /// credit 0 ether due to transferring funds from strategy to vault
            3000
        );
        /// debtratio: 30% of funds shared with strategy

        vm.expectEmit();
        emit Harvested(0, 0, 3 ether, 0);
        /// 10 ETH loss

        uint256 vaultBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));
        uint256 strategyBalanceBefore = IERC20(stakingRewards).balanceOf(address(strategy));
        uint256 expectedShareDecrease = strategy.sharesForAmount(3 ether);
        // here requesting 20% wont have any effect neither
        strategy.harvest(0, 0, 2000, address(0));

        data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(vault.totalDebt(), 27 ether);
        assertEq(data.strategyDebtRatio, 3000);
        assertEq(data.strategyTotalDebt, 27 ether);
        assertEq(data.strategyTotalLoss, 10 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), vaultBalanceBefore + 3 ether);
        assertLe(IERC20(stakingRewards).balanceOf(address(strategy)), strategyBalanceBefore - expectedShareDecrease);
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST previewLiquidate()               ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__PreviewLiquidate() public {
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

    /*     function testYearnAjnaWETH_Staking__PreviewLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount > 1e16 && amount <= 1000 ether);
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
    } */

    ////////////////////////////////////////////////////////////////
    ///                     TEST previewLiquidateExact()        ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__PreviewLiquidateExact() public {
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

    /*     function testYearnAjnaWETH_Staking__PreviewLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount > 1e16 && amount <= 1000 ether);
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
    } */

    ////////////////////////////////////////////////////////////////
    ///                     TEST maxLiquidateExact()                    ///
    ////////////////////////////////////////////////////////////////
    function testYearnAjnaWETH_Staking__maxLiquidateExact() public {
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
    /* 
    function testYearnAjnaWETH_Staking__maxLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount > 1e16 && amount <= 1000 ether);
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
    }
    */
    ////////////////////////////////////////////////////////////////
    ///                     TEST maxWithdraw()                   ///
    ////////////////////////////////////////////////////////////////

    function testYearnAjnaWETH_Staking__MaxLiquidate() public {
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

    /*     function testYearnAjnaWETH_Staking__MaxLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount > 1e16 && amount <= 1000 ether);
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
}
