// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import { BaseTest, IERC20, Vm, console2 } from "../../base/BaseTest.t.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { IConvexBooster } from "src/interfaces/IConvexBooster.sol";
import { IUniswapV3Router as IRouter } from "src/interfaces/IUniswap.sol";

import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { ConvexdETHFrxETHStrategyEvents } from "../../helpers/ConvexdETHFrxETHStrategyEvents.sol";
import { ConvexPools } from "../../helpers/ConvexPools.sol";
import { ConvexCrvUSDWethCollateralStrategyWrapper } from "../../mock/ConvexCrvUSDWethCollateralStrategyWrapper.sol";
import { MockConvexBooster } from "../../mock/MockConvexBooster.sol";
import { MockCurvePool } from "../../mock/MockCurvePool.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";

contract ConvexCrvUSDWethCollateralStrategyTest is BaseTest, ConvexdETHFrxETHStrategyEvents, ConvexPools {
    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    address public TREASURY;
    IStrategyWrapper public strategy;
    ConvexCrvUSDWethCollateralStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function setUp() public {
        super._setUp("MAINNET");
        vm.rollFork(20_074_046);

        TREASURY = makeAddr("treasury");

        /// Deploy MaxApyVault
        vaultDeployment = new MaxApyVault(address(this), USDC_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));

        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(users.alice);
        /// Deploy strategy implementation
        implementation = new ConvexCrvUSDWethCollateralStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        /// Deploy transparent upgradeable proxy
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy dETH<>frxETH Strategy")),
                users.alice,
                0x5AE28c9197a4a6570216fC7e53E7e0221D7A0FEF,
                0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));

        strategy = IStrategyWrapper(address(_proxy));

        /// Alice approves vault for deposits
        IERC20(USDC_MAINNET).approve(address(vault), type(uint256).max);
        vm.label(0x5AE28c9197a4a6570216fC7e53E7e0221D7A0FEF, "CURVE_CRVUSD_LENDING_POOL");
        vm.label(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E, "CURVE_CRVUSD_USDC_SWAP_POOL");
    }

    /*==================INITIALIZATION TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///                  TEST initialize()                       ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__Initialization() public {
        /// *************** Convex Strategy initialization *************** ///
        /// Deploy MaxApyVault
        MaxApyVault _vault = new MaxApyVault(address(this), USDC_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);

        /// Deploy transparent upgradeable proxy admin
        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        /// Deploy strategy implementation
        ConvexCrvUSDWethCollateralStrategyWrapper _implementation = new ConvexCrvUSDWethCollateralStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        /// Deploy transparent upgradeable proxy
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(_vault),
                keepers,
                bytes32(abi.encode("MaxApy dETH<>frxETH Strategy")),
                users.alice,
                0x5AE28c9197a4a6570216fC7e53E7e0221D7A0FEF,
                0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E
            )
        );

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));

        /// *************** Tests *************** ///
        /// Assert vault is set to MaxApy vault deployed in setup
        assertEq(_strategy.vault(), address(_vault));
        /// Assert maxapy vault obtains `VAULT_ROLE`
        assertEq(_strategy.hasAnyRole(address(_vault), _strategy.VAULT_ROLE()), true);
        /// Assert underlying asset is set to WETH
        assertEq(_strategy.underlyingAsset(), USDC_MAINNET);
        /// Assert strategy has approved vault to transfer underlying
        assertEq(IERC20(USDC_MAINNET).allowance(address(_strategy), address(_vault)), type(uint256).max);
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
        assertEq(_strategy.router(), 0xE592427A0AEce92De3Edee1F18E0157C05861564);

        assertEq(_strategy.curveLendingPool(), 0x5AE28c9197a4a6570216fC7e53E7e0221D7A0FEF);
        assertEq(_strategy.curveUsdcCrvUsdPool(), 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E);
        /// Assert pools are approved
        assertEq(
            IERC20(_strategy.curveLendingPool()).allowance(address(_strategy), address(_strategy.convexBooster())),
            type(uint256).max
        );
        assertEq(IERC20(CRV_MAINNET).allowance(address(_strategy), address(_strategy.router())), type(uint256).max);
        assertEq(IERC20(CVX_MAINNET).allowance(address(_strategy), address(_strategy.router())), type(uint256).max);
        assertEq(
            IERC20(USDC_MAINNET).allowance(address(_strategy), address(_strategy.curveUsdcCrvUsdPool())),
            type(uint256).max
        );

        /// Assert maxSingleTrade
        assertEq(_strategy.maxSingleTrade(), 1000 * 1e6);

        /// Assert minSwapCrv
        assertEq(_strategy.minSwapCrv(), 1e14);

        /// Assert minSwapCvx
        assertEq(_strategy.minSwapCvx(), 1e14);

        /// *************** Proxy values *************** ///
        /// Assert proxy admin contract owner is set to deployer (alice)
        assertEq(_proxyAdmin.owner(), users.alice);
        /// Assert proxy admin is set to the proxy admin contract
        vm.startPrank(address(_proxyAdmin));
        // assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    //  /*==================STRATEGY CONFIGURATION TESTS==================*/
    //  ////////////////////////////////////////////////////////////////
    //  ///                   TEST setEmergencyExit()                ///
    //  ////////////////////////////////////////////////////////////////

    function testConvexCrvUSDWethCollateral__SetEmergencyExit() public {
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
    function testConvexCrvUSDWethCollateral__SetMaxSingleTrade() public {
        /// Test unauthorized access with a user without privileges
        vm.stopPrank();
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMaxSingleTrade(1 * _1_USDC);

        /// Test unauthorized access with a user with `VAULT_ROLE`
        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMaxSingleTrade(1 * _1_USDC);

        /// Test set 0 amount
        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAmount()"));
        strategy.setMaxSingleTrade(0);

        /// Test proper max single trade setting
        vm.expectEmit();
        emit MaxSingleTradeUpdated(1 * _1_USDC);
        strategy.setMaxSingleTrade(1 * _1_USDC);
        assertEq(strategy.maxSingleTrade(), 1 * _1_USDC);
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST isActive()                      ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDC_MAINNET, address(strategy), 1 * _1_USDC);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.liquidateAllPositions();
        vm.startPrank(address(strategy));
        IERC20(USDC_MAINNET).transfer(makeAddr("random"), IERC20(USDC_MAINNET).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);
        /* 
        deal(USDC_MAINNET, address(strategy), 1 * _1_USDC);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0),block.timestamp);
        assertEq(strategy.isActive(), true); */
    }

    ////////////////////////////////////////////////////////////////
    ///                TEST setMinSwaps [CRV,CVX]                ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__SetMinSwaps() public {
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

    /*==================STRATEGY CORE LOGIC TESTS==================*/
    function testConvexCrvUSDWethCollateral__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// 1. Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        /// 2. Perform initial harvest to transfer funds to strategy
        strategy.harvest(0, 0, address(0), block.timestamp);

        /// 3. Compute expected amounts
        deal({ token: address(CRV_MAINNET), to: users.keeper, give: 10 ether });
        IERC20(CRV_MAINNET).approve(strategy.router(), type(uint256).max);

        bytes memory path = abi.encodePacked(
            CRV_MAINNET,
            uint24(3000), // CRV <> WETH 0.3%
            WETH_MAINNET,
            uint24(500), // WETH <> USDC 0.005%
            USDC_MAINNET
        );

        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(users.keeper);
        uint256 expectedAmountCrv = IRouter(strategy.router()).exactInput(
            IRouter.ExactInputParams({
                path: path,
                recipient: users.keeper,
                deadline: block.timestamp,
                amountIn: 10 ether,
                amountOutMinimum: 0
            })
        );
        uint256 balanceAfter = IERC20(USDC_MAINNET).balanceOf(users.keeper);

        /// 4. Strategy takes 10 ETH profit + CVX_MAINNET/CRV_MAINNET rewards
        /// Fake CRV_MAINNET + CVX_MAINNET rewards in strategy
        deal({ token: address(CRV_MAINNET), to: address(strategy), give: 10 ether });

        // Apply 1% difference
        uint256 minimumExpectedUSDCAmount = expectedAmountCrv * 999 / 10_000;

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(minimumExpectedUSDCAmount, type(uint256).max, address(0), block.timestamp);
    }
    ////////////////////////////////////////////////////////////////
    ///                   TEST _prepareReturn()                  ///
    ////////////////////////////////////////////////////////////////

    function testConvexCrvUSDWethCollateral__PrepareReturn() public {
        /// ⭕️ SCENARIO 1:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 40 * _1_USDC
        ///     - `totalAssets` = 40 * _1_USDC
        ///     - `shares` = 0
        ///     - `debt` = 40 * _1_USDC
        /// 2. Expected outcome:
        ///     - 2.1 Strategy has obtained profit, calculate profit.
        ///     - 2.2 Profit is 0 (not gt `underlyingBalance`) -> skip divesting from convex
        /// 3. Expected return values:
        ///     - `profit` -> 0
        ///     - `loss` -> 0
        ///     - `debtPayment` -> 1 * _1_USDC (value passed as `debtOutstanding`)

        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDC, 0);
        // assertEq(realizedProfit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, 1 * _1_USDC);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 2:
        /// 1. Initial State:
        ///     - `underlyingBalance` = 40 * _1_USDC
        ///     - `totalAssets` = around 100 * _1_USDC
        ///     - `debt` = 40 * _1_USDC
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
        ///     - `debtPayment` -> 1 * _1_USDC (value passed as `debtOutstanding`)
        snapshotId = vm.snapshot();
        deal({ token: USDC_MAINNET, to: address(strategy), give: 60 * _1_USDC });
        /// Perform initial investment in convex from the strategy side
        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertEq(unrealizedProfit, 59_988_000);
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

        /// no realizedProfit was made, setting the harvest to 20% has no effect
        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDC);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 4:
        /// 1. Initial State: Vault has 80 ETH profit. Withdrawal from vault is limited to 1000 wei, so
        /// `profit` will be > than `underlyingBalance`, setting profit to balance value
        snapshotId = vm.snapshot();

        deal({ token: USDC_MAINNET, to: address(strategy), give: 80 * _1_USDC });

        /// Perform initial investment in Convex from the strategy side
        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        /// Set `maxSingleTrade` to 1000 wei
        strategy.setMaxSingleTrade(1000);

        /// Fake report to increase `strategyTotalDebt`
        strategy.mockReport(0, 0, 0, TREASURY);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        /// Assert realizedProfit is set to the underlying balance of the strategy
        /// (which is the 40 ETH debt from the vault + the 1000 wei withdrawn (considering
        /// we tried to withdraw 1000 wei due to the `maxSingleTrade`))
        // assertEq(realizedProfit, 40 * _1_USDC + 1000);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _adjustPosition()                 ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__AdjustPosition() public {
        /// Test if `_underlyingBalance()` is 0, no investment is performed
        strategy.adjustPosition();
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        uint256 snapshotId = vm.snapshot();

        /// Perform 10 ETH investment
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedLp = strategy.lpForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.adjustPosition();
        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
        /// not accurate estimation due to slippage and bonus loses, which will be obtained later in withdrawal

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        /// Perform 100 ETH investment
        deal({ token: USDC_MAINNET, to: address(strategy), give: 100 * _1_USDC });
        expectedLp = strategy.lpForAmount(100 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 100 * _1_USDC);
        strategy.adjustPosition();
        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
        /// not accurate estimation due to slippage and bonus loses, which will be obtained later in withdrawal (around
        /// 2%)

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        /// Perform 500 ETH investment
        deal({ token: USDC_MAINNET, to: address(strategy), give: 500 * _1_USDC });
        expectedLp = strategy.lpForAmount(500 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 500 * _1_USDC);
        strategy.adjustPosition();

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
        /// not accurate estimation due to slippage and bonus loses, which will be obtained later in withdrawal (around
        /// 2.5%)

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _invest()                         ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__Invest() public {
        /// Test if `amount` is 0, no investment is performed
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        /// Test if `amount` is gt `_underlyingBalance()`, NotEnoughFundsToInvest() is thrown
        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        uint256 snapshotId = vm.snapshot();

        /// Perform 10 ETH investment
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedLp = strategy.lpForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 2 * _1_USDC);
        /// not accurate estimation due to slippage and bonus loses, which will be obtained later in withdrawal
        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        /// Check `maxSingleTrade` is selected as investment
        strategy.setMaxSingleTrade(1 * _1_USDC);
        /// Perform 10 ETH investment
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        expectedLp = strategy.lpForAmount(1 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 1 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 1 * _1_USDC);
        /// not accurate estimation due to slippage and bonus loses, which will be obtained later in withdrawal
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _divest()                         ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__Divest() public {
        /// Perform 10 ETH investment
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedLp = strategy.lpForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 1 * _1_USDC);
        /// not accurate estimation due to slippage and bonus loses, which will be obtained later in withdrawal

        /// Divest
        uint256 strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        uint256 amountDivested = strategy.divest(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)));

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidatePosition()                  ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__LiquidatePosition() public {
        /// Liquidate position where underlying balance can cover liquidation
        /// Scenario 1

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 * _1_USDC);
        assertEq(liquidatedAmount, 1 * _1_USDC);
        assertEq(loss, 0);

        /// Scenario 2
        (liquidatedAmount, loss) = strategy.liquidatePosition(10 * _1_USDC);
        assertEq(liquidatedAmount, 10 * _1_USDC);
        assertEq(loss, 0);

        /// Liquidate position where underlying balance can't cover liquidation
        /// Scenario 3
        deal({ token: USDC_MAINNET, to: address(strategy), give: 5 * _1_USDC });
        uint256 invested = strategy.invest(5 * _1_USDC, 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 * _1_USDC);
        assertGt(liquidatedAmount, 14 * _1_USDC);
        /// Small loss expected due to conversion between underlying and LP
        assertLt(loss, _1_USDC / 5);

        /// Scenario 4
        deal({ token: USDC_MAINNET, to: address(strategy), give: 50 * _1_USDC });
        invested = strategy.invest(50 * _1_USDC, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(50 * _1_USDC);

        assertGt(liquidatedAmount, 49 * _1_USDC);
        /// Small loss expected due to conversion between underlying and LP
        assertLt(loss, _1_USDC / 5);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST _liquidateAllPositions()              ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__LiquidateAllPositions() public {
        uint256 snapshotId = vm.snapshot();

        /// Perform 10 ETH investment
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedLp = strategy.lpForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 2 * _1_USDC);

        /// Liquidate
        uint256 strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();

        assertGt(amountFreed, 9 * _1_USDC);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        /// Perform 500 ETH investment
        deal({ token: USDC_MAINNET, to: address(strategy), give: 500 * _1_USDC });
        expectedLp = strategy.lpForAmount(500 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 500 * _1_USDC);
        strategy.invest(500 * _1_USDC, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 50 * _1_USDC);

        /// Liquidate
        strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();

        assertGt(amountFreed, 9 * _1_USDC);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST _unwindRewards()                  ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__UnwindRewards() public {
        /// Perform 10 ETH investment without rewards
        deal({ token: USDC_MAINNET, to: address(strategy), give: 100 * _1_USDC });
        vm.expectEmit();
        emit Invested(address(strategy), 100 * _1_USDC);
        strategy.invest(100 * _1_USDC, 0);

        strategy.unwindRewards();
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), 0, "1");

        /// Expect rewards in CVX, CRV
        vm.warp(block.timestamp + 30 days);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), 0, "2");
        strategy.unwindRewards();
        assertEq(IERC20(CVX_MAINNET).balanceOf(address(strategy)), 0, "3");
        assertEq(IERC20(CRV_MAINNET).balanceOf(address(strategy)), 0, "4");
        assertGt(IERC20(USDC_MAINNET).balanceOf(address(strategy)), 0, "5");
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST harvest()                       ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__Harvest() public {
        /// Try to harvest not being keeper
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, address(0), block.timestamp);

        /// ⭕️ SCENARIO 1:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy earns 10 ETH. Strategy performs second harvest to request more funds.

        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
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
            uint128(40 * _1_USDC),
            /// strategy total debt
            uint128(40 * _1_USDC),
            /// credit 40 * _1_USDC due to transferring funds from vault to strategy
            4000
        );
        /// debtratio not changed

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        /// 2. Perform initial harvest
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 expectedStrategyLpBalance = strategy.lpForAmount(40 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), 0);

        /// 2. Strategy takes 10 ETH profit + CVX_MAINNET/CRV_MAINNET rewards

        /// Fake gains in strategy (10 ETH = 40 ETH transferred previously + 10 ETH gains + CRV_MAINNET/CVX_MAINNET
        /// rewards)
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        vm.warp(block.timestamp + 1 days);
        uint256 beforeReportSnapshotId = vm.snapshot();

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);

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
            /// unrealized gain
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

        expectedStrategyLpBalance = strategy.lpForAmount(40 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);

        /// Step #2
        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        /// Step #3
        vm.startPrank(users.keeper);

        /// Fake gains in strategy (10 ETH = 40 ETH transferred previously + 10 ETH gains)
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        vm.warp(block.timestamp + 1 days);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 110_007_585);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3:
        /// 1. Strategy performs initial harvest to request vault funds
        /// 2. Strategy loses 10 ETH. Strategy performs second harvest and its debt ratio gets reduced
        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        expectedStrategyLpBalance = strategy.lpForAmount(40 * _1_USDC);
        /// Deposit into vault
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
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
            uint128(40 * _1_USDC),
            /// credit 40 * _1_USDC due to transferring funds from vault to strategy
            uint128(40 * _1_USDC),
            /// debtratio
            4000
        );
        /// debtratio not changed

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);

        /// 2. Strategy loses 10 ETH
        /// - Expected a 1000 reduction in debt ratio, 30% of total funds should be in the strategy
        /// - Total funds are now 90 ETH, 30% of which must be in strategy
        /// - 30% of 90 ETH = 27 ETH, but strategy still has 30 ETH -> there is a debt outstanding of 3 ETH
        /// Fake loss in strategy
        uint256 expectedLp = strategy.lpForAmount(10 * _1_USDC);

        vm.startPrank(address(strategy));
        uint256 withdrawn = strategy.divest(expectedLp);

        IERC20(USDC_MAINNET).transfer(makeAddr("random"), withdrawn);
        vm.startPrank(users.keeper);

        /// 10 USDC loss
        /// only losses, no effect
        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(data.strategyDebtRatio, 3001);
    }

    ////////////////////////////////////////////////////////////////
    ///                     TEST previewLiquidate()               ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 * _1_USDC);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(30 * _1_USDC);
        assertEq(expected, 30 * _1_USDC - loss);
    }

    /*     function testConvexCrvUSDWethCollateral__PreviewLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount >= 0.0001 * _1_USDC && amount <= 1000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDC_MAINNET, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0, address(this));
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(amount);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(amount);
        assertEq(expected, amount - loss);
    }
    */

    ////////////////////////////////////////////////////////////////
    ///                     TEST previewLiquidateExact()        ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(30 * _1_USDC);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
        strategy.liquidateExact(30 * _1_USDC);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, 30 * _1_USDC);
        // losses are equal or fewer than expected
        assertLe(withdrawn - 30 * _1_USDC, requestedAmount - 30 * _1_USDC);
    }

    /*  function testConvexCrvUSDWethCollateral__PreviewLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount >= 0.0001 * _1_USDC && amount <= 1000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDC_MAINNET, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);       
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0, address(this));
        vm.stopPrank();                                          
        uint256 requestedAmount = strategy.previewLiquidateExact(amount);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
        uint256 losses = strategy.liquidateExact(amount);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore ;
        // withdraw exactly what requested 
        assertEq(withdrawn, amount);
        // losses are equal or fewer than expected
        assertLe(losses , requestedAmount - amount);
    }
    */

    ////////////////////////////////////////////////////////////////
    ///                     TEST maxLiquidateExact()                    ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__maxLiquidateExact() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    }

    /*     function testConvexCrvUSDWethCollateral__maxLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount >= 0.0001 * _1_USDC && amount <= 1000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDC_MAINNET, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);       
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0, address(this));
        vm.stopPrank();                                                   
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore ;
        // withdraw exactly what requested 
        assertEq(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    }
    */
    ////////////////////////////////////////////////////////////////
    ///                     TEST maxWithdraw()                   ///
    ////////////////////////////////////////////////////////////////
    function testConvexCrvUSDWethCollateral__MaxLiquidate() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore;
        assertLe(withdrawn, maxWithdraw);
    }

    /*     function testConvexCrvUSDWethCollateral__MaxLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount >= 0.00001 * _1_USDC && amount <= 1000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDC_MAINNET, users.alice, amount * 2);
        vault.deposit(amount * 2,users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0,0,0, address(this));
        vm.stopPrank();                                          
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore ;
        assertLe(withdrawn, maxWithdraw);
    } */
}
