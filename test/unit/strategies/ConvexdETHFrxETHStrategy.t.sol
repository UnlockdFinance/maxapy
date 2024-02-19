// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import {BaseTest, IERC20, Vm, console} from "../../base/BaseTest.t.sol";
import {IMaxApyVaultV2} from "src/interfaces/IMaxApyVaultV2.sol";
import {ICurve} from "src/interfaces/ICurve.sol";
import {IConvexBooster} from "src/interfaces/IConvexBooster.sol";
import {IUniswapV2Router02 as IRouter} from "src/interfaces/IUniswap.sol";

import {MaxApyVaultV2} from "src/MaxApyVaultV2.sol";
import {StrategyData} from "src/helpers/VaultTypes.sol";
import {ConvexdETHFrxETHStrategy} from "src/strategies/WETH/convex/ConvexdETHFrxETHStrategy.sol";
import {ConvexdETHFrxETHStrategyEvents} from "../../helpers/ConvexdETHFrxETHStrategyEvents.sol";
import {ConvexPools} from "../../helpers/ConvexPools.sol";
import {ConvexdETHFrxETHStrategyWrapper} from "../../mock/ConvexdETHFrxETHStrategyWrapper.sol";
import {MockConvexBooster} from "../../mock/MockConvexBooster.sol";
import {MockCurvePool} from "../../mock/MockCurvePool.sol";
import {IStrategyWrapper} from "../../interfaces/IStrategyWrapper.sol";

contract ConvexdETHFrxETHStrategyTest is BaseTest, ConvexdETHFrxETHStrategyEvents, ConvexPools {
    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////
    IERC20 public constant crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public constant cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public constant frxEth = IERC20(0x5E8422345238F34275888049021821E8E08CAa1f);
    IRouter public constant SUSHISWAP_ROUTER = IRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    address public TREASURY;

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy;
    ConvexdETHFrxETHStrategyWrapper public implementation;
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
        vaultDeployment = new MaxApyVaultV2(WETH, "MaxApyWETHVault", "maxWETH", TREASURY);

        vault = IMaxApyVaultV2(address(vaultDeployment));

        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin();
        /// Deploy strategy implementation
        implementation = new ConvexdETHFrxETHStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        /// Deploy transparent upgradeable proxy
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
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

        strategy = IStrategyWrapper(address(_proxy));

        /// Alice approves vault for deposits
        IERC20(WETH).approve(address(vault), type(uint256).max);
    }

    /*==================INITIALIZATION TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///                  TEST initialize()                       ///
    ////////////////////////////////////////////////////////////////
    function testConvexdETHFrxETH__Initialization() public {
        /// *************** Convex Strategy initialization *************** ///
        /// Deploy MaxApyVaultV2
        MaxApyVaultV2 _vault = new MaxApyVaultV2(WETH, "MaxApyWETHVault", "maxWETH", TREASURY);

        /// Deploy transparent upgradeable proxy admin
        ProxyAdmin _proxyAdmin = new ProxyAdmin();
        /// Deploy strategy implementation
        ConvexdETHFrxETHStrategyWrapper _implementation = new ConvexdETHFrxETHStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        /// Deploy transparent upgradeable proxy
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address)",
                address(_vault),
                keepers,
                bytes32(abi.encode("MaxApy dETH<>frxETH Strategy")),
                users.alice,
                DETH_FRXETH_CURVE_POOL,
                ETH_FRXETH_CURVE_POOL,
                SUSHISWAP_ROUTER
            )
        );

        ITransparentUpgradeableProxy proxyInit = ITransparentUpgradeableProxy(address(_proxy));

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));

        /// *************** Tests *************** ///
        /// Assert vault is set to MaxApy vault deployed in setup
        assertEq(_strategy.vault(), address(_vault));
        /// Assert maxapy vault obtains `VAULT_ROLE`
        assertEq(_strategy.hasAnyRole(address(_vault), _strategy.VAULT_ROLE()), true);
        /// Assert underlying asset is set to WETH
        assertEq(_strategy.underlyingAsset(), WETH);
        /// Assert strategy has approved vault to transfer underlying
        assertEq(IERC20(WETH).allowance(address(_strategy), address(_vault)), type(uint256).max);
        /// Assert keeper user has `KEEPER_ROLE` granted
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        /// Assert alice (deployer) has `ADMIN_ROLE` granted and is owner
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);
        assertEq(_strategy.owner(), users.alice);
        /// Assert strategy name is correct
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy Convex ETH Strategy")));
        /// Assert convex booster is set to CONVEX_BOOSTER_MAINNET
        assertEq(_strategy.convexBooster(), CONVEX_BOOSTER_MAINNET);
        /// Assert router is correctly set
        assertEq(_strategy.router(), address(SUSHISWAP_ROUTER));

        /// Assert rewardpool, lp token and rewardToken are set to adequate values
      /*   assertNotEq(_strategy.convexRewardPool(), address(0));
        assertNotEq(_strategy.convexLpToken(), address(0));
        assertNotEq(_strategy.rewardToken(), address(0)); */

        /// Assert crvWethPool and cvxWethPool are properly initialized
        assertEq(_strategy.curveDEthFrxEthPool(), DETH_FRXETH_CURVE_POOL);
        assertEq(_strategy.curveEthFrxEthPool(), ETH_FRXETH_CURVE_POOL);
        /// Assert pools are approved
        assertEq(
            IERC20(_strategy.curveDEthFrxEthPool()).allowance(address(_strategy), address(_strategy.convexBooster())),
            type(uint256).max
        );
        assertEq(IERC20(crv).allowance(address(_strategy), address(_strategy.router())), type(uint256).max);
        assertEq(IERC20(cvx).allowance(address(_strategy), address(_strategy.cvxWethPool())), type(uint256).max);
        assertEq(
            IERC20(frxEth).allowance(address(_strategy), address(_strategy.curveEthFrxEthPool())), type(uint256).max
        );

        /// Assert maxSingleTrade
        assertEq(_strategy.maxSingleTrade(), 1_000 * 1e18);

        /// Assert minSwapCrv
        assertEq(_strategy.minSwapCrv(), 1e17);

        /// Assert minSwapCvx
        assertEq(_strategy.minSwapCvx(), 1e18);

        /// *************** Proxy values *************** ///
        /// Assert proxy admin contract owner is set to deployer (alice)
        assertEq(_proxyAdmin.owner(), users.alice);
        /// Assert proxy admin is set to the proxy admin contract
        vm.startPrank(address(_proxyAdmin));
        assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    //  /*==================STRATEGY CONFIGURATION TESTS==================*/
    //  ////////////////////////////////////////////////////////////////
    //  ///                   TEST setEmergencyExit()                ///
    //  ////////////////////////////////////////////////////////////////

    function testConvexdETHFrxETH__SetEmergencyExit() public {
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
    function testConvexdETHFrxETH__SetMaxSingleTrade() public {
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
    ///                     TEST isActive()                      ///
    ////////////////////////////////////////////////////////////////
    function testConvexdETHFrxETH__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(WETH, address(strategy), 1 ether);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.liquidateAllPositions();
        vm.startPrank(address(strategy));
        IERC20(WETH).transfer(makeAddr("random"), IERC20(WETH).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);
/* 
        deal(WETH, address(strategy), 1 ether);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0);
        assertEq(strategy.isActive(), true); */
    }

    ////////////////////////////////////////////////////////////////
    ///                TEST setMinSwaps [CRV,CVX]                ///
    ////////////////////////////////////////////////////////////////
    function testConvexdETHFrxETH__SetMinSwaps() public {
        // Negatives
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSwapCrv(1e19);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSwapCvx(1e19);

        // Positives
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit MinSwapCrvUpdated(1e19);
        strategy.setMinSwapCrv(1e19);
        assertEq(strategy.minSwapCrv(), 10e18);

        vm.expectEmit();
        emit MinSwapCvxUpdated(1e20);
        strategy.setMinSwapCvx(1e20);
        assertEq(strategy.minSwapCvx(), 1e20);
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST setRouter                       ///
    ////////////////////////////////////////////////////////////////
    function testConvexdETHFrxETH__SetRouter() public {
        address router = makeAddr("router");
        address router2 = makeAddr("router2");
        // Negatives
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setRouter(router);

        // Positives
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit RouterUpdated(router);
        strategy.setRouter(router);
        assertEq(crv.allowance(address(strategy), router), type(uint256).max);

        vm.expectEmit();
        emit RouterUpdated(router2);
        strategy.setRouter(router2);
        assertEq(crv.allowance(address(strategy), router), 0);
        assertEq(crv.allowance(address(strategy), router2), type(uint256).max);
    }

    /*==================STRATEGY CORE LOGIC TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///                      TEST slippage                       ///
    ////////////////////////////////////////////////////////////////
    function testConvexdETHFrxETH__Slippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// 1. Deposit into vault
        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        /// 2. Perform initial harvest to transfer funds to strategy
        strategy.harvest(0, 0, 0);

        /// 3. Compute expected amounts
        deal({token: address(crv), to: users.keeper, give: 10 ether});
        deal({token: address(cvx), to: users.keeper, give: 10 ether});
        crv.approve(strategy.router(), type(uint256).max);
        cvx.approve(strategy.cvxWethPool(), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(crv);
        path[1] = WETH;

        uint256[] memory expectedAmountCrv =
            IRouter(strategy.router()).swapExactTokensForTokens(10 ether, 0, path, users.keeper, block.timestamp);

        uint256 expectedAmountCvx = ICurve(strategy.cvxWethPool()).exchange(1, 0, 10 ether, 0, false);

        /// 4. Strategy takes 10 ETH profit + cvx/crv rewards
        /// Fake crv + cvx rewards in strategy
        deal({token: address(crv), to: address(strategy), give: 10 ether});
        deal({token: address(cvx), to: address(strategy), give: 10 ether});

        // Apply 1% difference
        uint256 minimumExpectedEthAmount = (expectedAmountCrv[1] + expectedAmountCvx) * 9999 / 10_000;
        // Setting a higher amount should fail
        vm.expectRevert(abi.encodeWithSignature("MinExpectedBalanceAfterSwapNotReached()"));
        strategy.harvest(expectedAmountCrv[1] + expectedAmountCvx + 1, 0, 10_000);

        // Setting a proper amount should allow swapping
        strategy.harvest(minimumExpectedEthAmount, 0, 10_000);
    }

    function testConvexdETHFrxETH__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// 1. Deposit into vault
        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        /// 2. Perform initial harvest to transfer funds to strategy
        strategy.harvest(0, 0, 0);

        /// 3. Compute expected amounts
        deal({token: address(crv), to: users.keeper, give: 10 ether});
        deal({token: address(cvx), to: users.keeper, give: 10 ether});
        crv.approve(strategy.router(), type(uint256).max);
        cvx.approve(strategy.cvxWethPool(), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(crv);
        path[1] = WETH;

        uint256[] memory expectedAmountCrv =
            IRouter(strategy.router()).swapExactTokensForTokens(10 ether, 0, path, users.keeper, block.timestamp);

        uint256 expectedAmountCvx = ICurve(strategy.cvxWethPool()).exchange(1, 0, 10 ether, 0, false);

        /// 4. Strategy takes 10 ETH profit + cvx/crv rewards
        /// Fake crv + cvx rewards in strategy
        deal({token: address(crv), to: address(strategy), give: 10 ether});
        deal({token: address(cvx), to: address(strategy), give: 10 ether});

         // Apply 1% difference
        uint256 minimumExpectedEthAmount = (expectedAmountCrv[1] + expectedAmountCvx) * 9999 / 10_000;

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(minimumExpectedEthAmount, type(uint256).max, 0);
    }
    ////////////////////////////////////////////////////////////////
    ///                   TEST _prepareReturn()                  ///
    ////////////////////////////////////////////////////////////////

    function testConvexdETHFrxETH__PrepareReturn() public {
        /// ⭕️ SCENARIO 1:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 40 ether
        ///     - `totalAssets` = 40 ether
        ///     - `shares` = 0
        ///     - `debt` = 40 ether
        /// 2. Expected outcome:
        ///     - 2.1 Strategy has obtained profit, calculate profit.
        ///     - 2.2 Profit is 0 (not gt `underlyingBalance`) -> skip divesting from convex
        /// 3. Expected return values:
        ///     - `profit` -> 0
        ///     - `loss` -> 0
        ///     - `debtPayment` -> 1 ether (value passed as `debtOutstanding`)

        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0);

        (uint256 realizedProfit, uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 ether, 0, 0);
        assertEq(realizedProfit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, 1 ether);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 2:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 40 ether
        ///     - `totalAssets` = around 100 ether
        ///     - `debt` = 40 ether
        /// 2. Expected outcome:
        ///     - 2.1 Strategy has obtained profit, calculate profit.
        ///     - 2.2 Profit is around 60 ETH (it is greater than `underlyingBalance`)
        ///            -> divest from convex to obtain an extra 60 ETH
        ///     - 2.3 `amountToWithdraw` is 60 ETH, strategy holds 40 ETH already
        ///            -> `expectedAmountToWithdraw` is 20 ETH
        ///     - 2.4 Divesting causes 1 wei loss
        ///     - 2.5 `profit` >= `loss` -> profit -= loss;
        /// 3. Expected return values:
        ///     - `profit` -> around 60 ETH
        ///     - `loss` -> 0
        ///     - `debtPayment` -> 1 ether (value passed as `debtOutstanding`)
        snapshotId = vm.snapshot();
        deal({token: WETH, to: address(strategy), give: 60 ether});
        /// Perform initial investment in convex from the strategy side
        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 0);

        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 60.000917856955753877 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 10_000);

        assertEq(realizedProfit, 59.936474328397156010 ether);
        assertEq(unrealizedProfit, 60.000917856955753877  ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 3_000);

        assertEq(realizedProfit, 18.000275357086726163 ether);
        assertEq(unrealizedProfit, 60.000917856955753877  ether);
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
        strategy.mockReport(0, 0, 0);

        /// Fake strategy loss of 10 ETH
        strategy.triggerLoss(10 ether);

        /// no realizedProfit was made, setting the harvest to 20% has no effect
        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 2_000);

        assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 ether);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 4:
        /// 1. Initial State: Vault has 80 ETH profit. Withdrawal from vault is limited to 1000 wei, so
        /// `profit` will be > than `underlyingBalance`, setting profit to balance value
        snapshotId = vm.snapshot();

        deal({token: WETH, to: address(strategy), give: 80 ether});

        /// Perform initial investment in Convex from the strategy side
        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        /// Set `maxSingleTrade` to 1000 wei
        strategy.setMaxSingleTrade(1000);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0);

        (realizedProfit, unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0, 10_000);

        /// Assert realizedProfit is set to the underlying balance of the strategy
        /// (which is the 40 ETH debt from the vault + the 1000 wei withdrawn (considering
        /// we tried to withdraw 1000 wei due to the `maxSingleTrade`))
        assertEq(realizedProfit, 40 ether + 1000);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _adjustPosition()                 ///
    ////////////////////////////////////////////////////////////////
    function testConvexdETHFrxETH__AdjustPosition() public {
        /// Test if `_underlyingBalance()` is 0, no investment is performed
        strategy.adjustPosition();
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        uint256 snapshotId = vm.snapshot();

        /// Perform 10 ETH investment
        deal({token: WETH, to: address(strategy), give: 10 ether});
        uint256 expectedLp = strategy.lpForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.adjustPosition();
        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
        /// not accurate estimation due to slippage and bonus loses, which will be obtained later in withdrawal

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        /// Perform 100 ETH investment
        deal({token: WETH, to: address(strategy), give: 100 ether});
        expectedLp = strategy.lpForAmount(100 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 100 ether);
        strategy.adjustPosition();
        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
        /// not accurate estimation due to slippage and bonus loses, which will be obtained later in withdrawal (around 2%)

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        /// Perform 500 ETH investment
        deal({token: WETH, to: address(strategy), give: 500 ether});
        expectedLp = strategy.lpForAmount(500 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 500 ether);
        strategy.adjustPosition();

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
        /// not accurate estimation due to slippage and bonus loses, which will be obtained later in withdrawal (around 2.5%)

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _invest()                         ///
    ////////////////////////////////////////////////////////////////
    function testConvexdETHFrxETH__Invest() public {
        /// Test if `amount` is 0, no investment is performed
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        /// Test if `amount` is gt `_underlyingBalance()`, NotEnoughFundsToInvest() is thrown
        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        uint256 snapshotId = vm.snapshot();

        /// Perform 10 ETH investment
        deal({token: WETH, to: address(strategy), give: 10 ether});
        uint256 expectedLp = strategy.lpForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 2 ether);
        /// not accurate estimation due to slippage and bonus loses, which will be obtained later in withdrawal
        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        /// Check `maxSingleTrade` is selected as investment
        strategy.setMaxSingleTrade(1 ether);
        /// Perform 10 ETH investment
        deal({token: WETH, to: address(strategy), give: 10 ether});
        expectedLp = strategy.lpForAmount(1 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 1 ether);
        strategy.invest(10 ether, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 1 ether);
        /// not accurate estimation due to slippage and bonus loses, which will be obtained later in withdrawal
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _divest()                         ///
    ////////////////////////////////////////////////////////////////
    function testConvexdETHFrxETH__Divest() public {
        /// Perform 10 ETH investment
        deal({token: WETH, to: address(strategy), give: 10 ether});
        uint256 expectedLp = strategy.lpForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 1 ether);
        /// not accurate estimation due to slippage and bonus loses, which will be obtained later in withdrawal

        /// Divest
        uint256 strategyBalanceBefore = IERC20(WETH).balanceOf(address(strategy));
        uint256 amountDivested = strategy.divest(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)));

        assertEq(IERC20(WETH).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidatePosition()                  ///
    ////////////////////////////////////////////////////////////////
    function testConvexdETHFrxETH__LiquidatePosition() public {
        /// Liquidate position where underlying balance can cover liquidation
        /// Scenario 1

        deal({token: WETH, to: address(strategy), give: 10 ether});
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 ether);
        assertEq(liquidatedAmount, 1 ether);
        assertEq(loss, 0);

        /// Scenario 2
        (liquidatedAmount, loss) = strategy.liquidatePosition(10 ether);
        assertEq(liquidatedAmount, 10 ether);
        assertEq(loss, 0);

        /// Liquidate position where underlying balance can't cover liquidation
        /// Scenario 3
        deal({token: WETH, to: address(strategy), give: 5 ether});
        uint256 invested = strategy.invest(5 ether, 0);

        deal({token: WETH, to: address(strategy), give: 10 ether});
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 ether);
        assertGt(liquidatedAmount, 14.99 ether);
        /// Small loss expected due to conversion between underlying and LP
        assertLt(loss, 0.2 ether);

        /// Scenario 4
        deal({token: WETH, to: address(strategy), give: 50 ether});
        invested = strategy.invest(50 ether, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(50 ether);

        assertGt(liquidatedAmount, 49.9 ether);
        /// Small loss expected due to conversion between underlying and LP
        assertLt(loss, 0.2 ether);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidateAllPositions()              ///
    ////////////////////////////////////////////////////////////////
    function testConvexdETHFrxETH__LiquidateAllPositions() public {
        uint256 snapshotId = vm.snapshot();

        /// Perform 10 ETH investment
        deal({token: WETH, to: address(strategy), give: 10 ether});
        uint256 expectedLp = strategy.lpForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 2 ether);

        /// Liquidate
        uint256 strategyBalanceBefore = IERC20(WETH).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();

        assertGt(amountFreed, 9 ether);

        assertEq(IERC20(WETH).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        /// Perform 500 ETH investment
        deal({token: WETH, to: address(strategy), give: 500 ether});
        expectedLp = strategy.lpForAmount(500 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 500 ether);
        strategy.invest(500 ether, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 50 ether);

        /// Liquidate
        strategyBalanceBefore = IERC20(WETH).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();

        assertGt(amountFreed, 9 ether);

        assertEq(IERC20(WETH).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _unwindRewards()                  ///
    ////////////////////////////////////////////////////////////////
    function testConvexdETHFrxETH__UnwindRewards() public {
        /// Perform 10 ETH investment without rewards
        deal({token: WETH, to: address(strategy), give: 100 ether});
        vm.expectEmit();
        emit Invested(address(strategy), 100 ether);
        strategy.invest(100 ether, 0);

        strategy.unwindRewards();
        assertEq(IERC20(WETH).balanceOf(address(strategy)), 0);

        /// Expect rewards in CVX, CRV
        vm.warp(block.timestamp + 30 days);

        assertEq(IERC20(WETH).balanceOf(address(strategy)), 0);
        strategy.unwindRewards();
        assertEq(IERC20(cvx).balanceOf(address(strategy)), 0);
        assertEq(IERC20(crv).balanceOf(address(strategy)), 0);
        assertGt(IERC20(WETH).balanceOf(address(strategy)), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST harvest()                       ///
    ////////////////////////////////////////////////////////////////

    function testSommelierTurboStEth__Harvest_Negatives() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);
        
        // it should revert if profit harvest percentage is > 100 %
        vm.startPrank(users.keeper);
        vm.expectRevert(abi.encodeWithSignature("InvalidHarvestedProfit()"));
        strategy.harvest(0, 0, 10_001);
    }

    function testConvexdETHFrxETH__Harvest() public {
        /// Try to harvest not being keeper
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, 0);

        /// ⭕️ SCENARIO 1:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy earns 10 ETH. Strategy performs second harvest to request more funds.

        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            /// vault gain
            0,
            /// unrealized gain
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

        /// 2. Perform initial harvest
        strategy.harvest(0, 0, 0);

        uint256 expectedStrategyLpBalance = strategy.lpForAmount(40 ether);
        assertEq(IERC20(WETH).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(WETH).balanceOf(address(strategy)), 0);

        
        /// 2. Strategy takes 10 ETH profit + cvx/crv rewards

        /// Fake gains in strategy (10 ETH = 40 ETH transferred previously + 10 ETH gains + crv/cvx rewards)
        deal({token: WETH, to: address(strategy), give: 10 ether});
        vm.warp(block.timestamp + 1 days);
        uint256 beforeReportSnapshotId = vm.snapshot();

        /// Case #1: Harvest 100% of the profit
        strategy.harvest(0, 0, 10_000);
        assertEq(IERC20(WETH).balanceOf(address(vault)), 70.054691538051257490 ether);

        vm.revertTo(beforeReportSnapshotId);

        /// Case #2: Harvest 50% of the profit
        strategy.harvest(0, 0, 5_000);
        assertEq(IERC20(WETH).balanceOf(address(vault)), 65.027345769025628745 ether);

        vm.revertTo(beforeReportSnapshotId);
        /// Case #3: Harvest 0% of the profit
        strategy.harvest(0, 0, 0);
        assertEq(IERC20(WETH).balanceOf(address(vault)), 60 ether);

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
            /// vault gain
            0,
            /// unrealized gain
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

        strategy.harvest(0, 0, 0);

        expectedStrategyLpBalance = strategy.lpForAmount(40 ether);
        assertEq(IERC20(WETH).balanceOf(address(vault)), 60 ether);

        /// Step #2
        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        /// Step #3
        vm.startPrank(users.keeper);

        /// Fake gains in strategy (10 ETH = 40 ETH transferred previously + 10 ETH gains)
        deal({token: WETH, to: address(strategy), give: 10 ether});
        vm.warp(block.timestamp + 1 days);

        strategy.harvest(0, 0, 2_000);
        assertEq(IERC20(WETH).balanceOf(address(vault)), 110.011279484032002561 ether);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy loses 10 ETH. Strategy performs second harvest and its debt ratio gets reduced
        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        expectedStrategyLpBalance = strategy.lpForAmount(40 ether);
        /// Deposit into vault
        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            /// vault realized gain
            0,
            /// vault unrealized gain
            0,
            /// vault loss
            0,
            /// vault debtPayment
            0,
            /// strategy gain
            0,
            /// strategy loss
            0,
            /// strategy total debt
            40 ether,
            /// credit 40 ether due to transferring funds from vault to strategy
            40 ether,
            /// debtratio
            4000
        );
        /// debtratio not changed

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, 0);

        assertEq(IERC20(WETH).balanceOf(address(vault)), 60 ether);

        /// 2. Strategy loses 10 ETH
        /// - Expected a 1000 reduction in debt ratio, 30% of total funds should be in the strategy
        /// - Total funds are now 90 ETH, 30% of which must be in strategy
        /// - 30% of 90 ETH = 27 ETH, but strategy still has 30 ETH -> there is a debt outstanding of 3 ETH
        /// Fake loss in strategy
        uint256 expectedLp = strategy.lpForAmount(10 ether);

        vm.startPrank(address(strategy));
        uint256 withdrawn = strategy.divest(expectedLp);

        IERC20(WETH).transfer(makeAddr("random"), withdrawn);
        vm.startPrank(users.keeper);

        /// 10 USDC loss
        /// only losses, no effect
        strategy.harvest(0, 0, 1_000);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 2996);
        assertEq(data.strategyDebtRatio, 2996);
    }

    function testConvexdETHFrxETH__PreviewWithdraw() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether + 723874239,users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0);
        vm.stopPrank();
        uint256 expected = strategy.previewWithdraw(30 ether);
        vm.startPrank(address(vault));
        uint256 loss = strategy.withdraw(30 ether);
        assertEq(expected, 30 ether - loss);
    }

}
