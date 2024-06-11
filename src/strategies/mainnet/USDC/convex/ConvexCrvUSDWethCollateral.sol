// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    BaseConvexStrategy, BaseStrategy, IMaxApyVault, SafeTransferLib
} from "src/strategies/base/BaseConvexStrategy.sol";
import { IConvexBooster } from "src/interfaces/IConvexBooster.sol";
import { IConvexRewards } from "src/interfaces/IConvexRewards.sol";
import { IUniswapV2Router02 as IRouter } from "src/interfaces/IUniswap.sol";
import { ICurveLpPool, ICurveLendingPool } from "src/interfaces/ICurve.sol";
import { IWETH } from "src/interfaces/IWETH.sol";

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

/// @title ConvexCrvUSDWethCollateral
/// @author MaxApy
/// @notice `ConvexCrvUSDWethCollateral` supplies ETH into the dETH-crvUsd pool in Curve, then stakes the curve LP
/// in Convex in order to maximize yield.
contract ConvexCrvUSDWethCollateral is BaseConvexStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////

    /// @notice Ethereum mainnet's CRV Token
    address public constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    /// @notice Ethereum mainnet's CVX Token
    address public constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    /// @notice Ethereum mainnet's crvUsd Token
    address public constant crvUsd = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    /// @notice Main Convex's deposit contract for LP tokens
    IConvexBooster public constant convexBooster = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    /// @notice CVX-WETH pool in Curve
    ICurve public constant cvxWethPool = ICurve(0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4);
    /// @notice Identifier for the crvUsd(WETH collateral) Convex lending pool
    uint256 public constant CRVUSD_WETH_COLLATERAL_POOL_ID = 326;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////

    /*==================CURVE-RELATED STORAGE VARIABLES==================*/
    /// @notice Main Curve pool for this Strategy
    ICurveLendingPool public curveLendingPool;

    /*==================CURVE-RELATED STORAGE VARIABLES==================*/
    /// @notice Curve's usdc-crvUsd pool
    ICurve public curveUsdcCrvUsdPool;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _curveLendingPool The address of the strategy's main Curve pool, dETH-crvUsd pool
    /// @param _curveUsdcCrvUsdPool The address of Curve's ETH-crvUsd pool
    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        ICurveLendingPool _curveLendingPool,
        ICurveLpPool _curveUsdcCrvUsdPool
    )
        public
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);

        // Fetch convex pool data
        (, address _token,, address _crvRewards,, bool _shutdown) =
            convexBooster.poolInfo(CRVUSD_WETH_COLLATERAL_POOL_ID);

        assembly {
            // Check if Convex pool is in shutdown mode
            if eq(_shutdown, 0x01) {
                // throw the `ConvexPoolShutdown` error
                mstore(0x00, 0xcff936d6)
                revert(0x1c, 0x04)
            }
        }

        convexRewardPool = IConvexRewards(_crvRewards);
        convexLpToken = _token;
        rewardToken = IConvexRewards(_crvRewards).rewardToken();

        // Curve init
        curveLendingPool = _curveLendingPool;
        curveUsdcCrvUsdPool = _curveUsdcCrvUsdPool;

        // Approve pools
        address(_curveLendingPool).safeApprove(address(convexBooster), type(uint256).max);

        crv.safeApprove(address(_router), type(uint256).max);
        cvx.safeApprove(address(cvxWethPool), type(uint256).max);
        crvUsd.safeApprove(address(curveLendingPool), type(uint256).max);
        crvUsd.safeApprove(address(curveUsdcCrvUsdPool), type(uint256).max);

        maxSingleTrade = 1000 * 1e6;

        minSwapCrv = 1e17;
        minSwapCvx = 1e18;
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////
    /// @notice Invests `amount` of underlying into the Convex pool
    /// @dev We don't perform any reward claim. All assets must have been
    /// previously converted to `underlyingAsset`.
    /// Note that because of Curve's bonus/penalty approach, we check if it is best to
    /// add liquidity with native ETH or with pegged ETH. It is then expected to always receive
    /// at least `amount` if we perform an exchange from ETH to pegged ETH.
    /// @param amount The amount of underlying to be deposited in the pool
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Curve LP tokens)
    /// @return The amount of tokens received, in terms of underlying
    function _invest(uint256 amount, uint256 minOutputAfterInvestment) internal override returns (uint256) {
        // Don't do anything if amount to invest is 0
        if (amount == 0) return 0;

        uint256 underlyingBalance = _underlyingBalance();

        assembly ("memory-safe") {
            if gt(amount, underlyingBalance) {
                // throw the `NotEnoughFundsToInvest` error
                mstore(0x00, 0xb2ff68ae)
                revert(0x1c, 0x04)
            }
        }

        // Invested amount will be a maximum of `maxSingleTrade`
        amount = Math.min(maxSingleTrade, amount);

        // Swap USDC for crvUsd
        uint256 crvUsdReceived = curveUsdcCrvUsdPool.exchange(0, 1, amount, 0);

        // Add liquidity to the lending pool
        uint256 lpReceived = curveLendingPool.deposit(crvUsdReceived, address(this));

        assembly ("memory-safe") {
            // if (lpReceived < minOutputAfterInvestment)
            if lt(lpReceived, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        // Deposit Curve LP into Convex pool with id `CRVUSD_WETH_COLLATERAL_POOL_ID` and immediately stake convex LP
        // tokens
        // into the rewards contract
        convexBooster.deposit(CRVUSD_WETH_COLLATERAL_POOL_ID, lpReceived, true);

        emit Invested(address(this), amount);

        return _lpValue(lpReceived);
    }

    /// @notice Divests amount `amount` from the Convex pool
    /// Note that divesting from the pool could potentially cause loss, so the divested amount might actually be
    /// different from
    /// the requested `amount` to divest
    /// @dev care should be taken, as the `amount` parameter is not in terms of underlying,
    /// but in terms of Curve's LP tokens
    /// Note that if minimum withdrawal amount is not reached, funds will not be divested, and this
    /// will be accounted as a loss later.
    /// @return the total amount divested, in terms of underlying asset
    function _divest(uint256 amount) internal override returns (uint256) {
        // Withdraw from Convex and unwrap directly to Curve LP tokens
        convexRewardPool.withdrawAndUnwrap(amount, false);

        // Remove liquidity and obtain crvUsd
        uint256 amountWithdrawn = curveLendingPool.redeem(
            amount,
            address(this),
            address(this)
        );

        // Swap crvUsd for USDC
        uint256 usdcReceived = curveUsdcCrvUsdPool.exchange(1, 0, amountWithdrawn, 0);

        return usdcReceived;
    }

    /// @notice Claims rewards, converting them to `underlyingAsset`.
    /// @dev MinOutputAmounts are left as 0 and properly asserted globally on `harvest()`.
    function _unwindRewards(IConvexRewards rewardPool) internal override {
        // Claim CRV and CVX rewards
        rewardPool.getReward(address(this), true);

        // Exchange CRV <> WETH
        uint256 crvBalance = _crvBalance();
        if (crvBalance > minSwapCrv) {
            address[] memory path = new address[](2);
            path[0] = crv;
            path[1] = underlyingAsset;
            router.swapExactTokensForTokens(crvBalance, 0, path, address(this), block.timestamp);
        }

        // Exchange CVX <> WETH
        uint256 cvxBalance = _cvxBalance();
        if (cvxBalance > minSwapCvx) {
            cvxWethPool.exchange(1, 0, cvxBalance, 0, false);
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                    VIEW FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////
    /// @notice This function is meant to be called from the vault
    /// @dev calculates the estimated real output of a withdrawal(including losses) for a @param requestedAmount
    /// for the vault to be able to provide an accurate amount when calling `previewRedeem`
    /// @return liquidatedAmount output in assets
    function previewLiquidate(uint256 requestedAmount)
        public
        view
        virtual
        override
        returns (uint256 liquidatedAmount)
    {
        uint256 loss;
        uint256 underlyingBalance = _underlyingBalance();
        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the Curve liquidity pool
        if (underlyingBalance < requestedAmount) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = requestedAmount - underlyingBalance;
            }
            uint256 value = _lpForAmount(amountToWithdraw);
            uint256 withdrawn = _lpValue(value);
            withdrawn = curveUsdcCrvUsdPool.get_dy(1, 0, withdrawn);
            if (withdrawn < amountToWithdraw) loss = amountToWithdraw - withdrawn;
        }
        liquidatedAmount = requestedAmount - loss;
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////
    /// @notice Determines how many lp tokens depositor of `amount` of underlying would receive.
    /// @dev Some loss of precision is occured, but it is not critical as this is only an underestimation of
    /// the actual assets, and profit will be later accounted for.
    /// @return returns the estimated amount of lp tokens computed in exchange for underlying `amount`
    function _lpValue(uint256 lp) internal view virtual returns (uint256) {
        return curveLendingPool.previewRedeem(lp);
    }

    /// @notice Determines how many lp tokens depositor of `amount` of underlying would receive.
    /// @return returns the estimated amount of lp tokens computed in exchange for underlying `amount`
    function _lpForAmount(uint256 amount) internal view virtual returns (uint256) {
        return curveLendingPool.convertToShares(amount);
    }

    /// @notice Returns the estimated price for the strategy's Convex's LP token
    /// @return returns the estimated lp token price
    function _lpPrice() internal view override returns (uint256) { }

    function _crv() internal pure override returns (address) {
        return crv;
    }

    function _cvx() internal pure override returns (address) {
        return cvx;
    }
}
