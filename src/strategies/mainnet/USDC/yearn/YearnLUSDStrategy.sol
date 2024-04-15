// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    BaseYearnV2Strategy,
    IMaxApyVaultV2,
    SafeTransferLib,
    IYVault,
    IERC20,
    Math
} from "src/strategies/base/BaseYearnV2Strategy.sol";
import {IUniswapV3Router as IRouter, IUniswapV3Pool} from "src/interfaces/IUniswap.sol";
import {OracleLibrary} from "src/lib/OracleLibrary.sol";
import "forge-std/console.sol";

/// @title YearnLUSDStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnLUSDStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnLUSDStrategy is BaseYearnV2Strategy {
    using SafeTransferLib for address;
    ////////////////////////////////////////////////////////////////
    ///                         EVENTS                           ///
    ////////////////////////////////////////////////////////////////

    /// @notice Emitted when the strategy's max single trade value is updated
    event MaxSingleTradeUpdated(uint256 maxSingleTrade);
    // @dev `keccak256(bytes("MaxSingleTradeUpdated(uint256)"))`.

    uint256 internal constant _MAX_SINGLE_TRADE_UPDATED_EVENT_SIGNATURE =
        0xe8b08f84dc067e4182670384e9556796d3a831058322b7e55f9ddb3ec48d7c10;
    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    /// @notice LUSD token address in mainnet
    address public constant lusd = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    /// @notice Router to perform USDC-LUSD swaps
    IRouter public constant router = IRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    /// @notice Address of Uniswap V3 USDC-LUSD pool
    address public constant pool = 0x4e0924d3a751bE199C426d52fb1f2337fa96f736;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////
    /// @notice Maximum trade size within the strategy
    uint256 public maxSingleTrade;

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _yVault The Yearn Finance vault this strategy will interact with
    function initialize(
        IMaxApyVaultV2 _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        IYVault _yVault
    ) public override initializer {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        yVault = _yVault;

        /// Approve Yearn Vault to transfer LUSD
        lusd.safeApprove(address(_yVault), type(uint256).max);

        /// Approve Uniswap router to transfer both tokens
        underlyingAsset.safeApprove(address(router), type(uint256).max);
        lusd.safeApprove(address(router), type(uint256).max);

        /// Mininmum single trade is 0.01 token units
        minSingleTrade = 10 ** IERC20(underlyingAsset).decimals() / 100;

        /// Max single treade
        maxSingleTrade = 10 ** IERC20(underlyingAsset).decimals() * 10_000;
    }

    ////////////////////////////////////////////////////////////////
    ///                 STRATEGY CONFIGURATION                   ///
    ////////////////////////////////////////////////////////////////

    /// @notice Sets the maximum single trade amount allowed
    /// @param _maxSingleTrade The new maximum single trade value
    function setMaxSingleTrade(uint256 _maxSingleTrade) external checkRoles(ADMIN_ROLE) {
        assembly ("memory-safe") {
            // revert if `_maxSingleTrade` is zero
            if iszero(_maxSingleTrade) {
                // throw the `InvalidZeroAmount` error
                mstore(0x00, 0xdd484e70)
                revert(0x1c, 0x04)
            }

            sstore(maxSingleTrade.slot, _maxSingleTrade) // set the max single trade value in storage

            // Emit the `MaxSingleTradeUpdated` event
            mstore(0x00, _maxSingleTrade)
            log1(0x00, 0x20, _MAX_SINGLE_TRADE_UPDATED_EVENT_SIGNATURE)
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Invests `amount` of underlying, depositing it in the Yearn Vault
    /// @param amount The amount of underlying to be deposited in the vault
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Yearn receipt tokens)
    /// @return depositedAmount The amount of shares received, in terms of underlying
    function _invest(uint256 amount, uint256 minOutputAfterInvestment)
        internal
        override
        returns (uint256 depositedAmount)
    {
        // Don't do anything if amount to invest is 0
        if (amount == 0) return 0;

        uint256 underlyingBalance = _underlyingBalance();
        if (amount > underlyingBalance) revert NotEnoughFundsToInvest();

        // swap the USDC to LUSD
        router.exactInputSingle(
            IRouter.ExactInputSingleParams({
                tokenIn: underlyingAsset,
                tokenOut: lusd,
                fee: 500,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: underlyingBalance,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 lusdBalance = _lusdBalance();

        uint256 shares = yVault.deposit(lusdBalance);

        assembly ("memory-safe") {
            // if (shares < minOutputAfterInvestment)
            if lt(shares, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        depositedAmount = _shareValue(shares);

        assembly {
            // Emit the `Invested` event
            mstore(0x00, amount)
            log2(0x00, 0x20, _INVESTED_EVENT_SIGNATURE, address())
        }
    }

    /// @notice Divests amount `shares` from Yearn Vault
    /// Note that divesting from Yearn could potentially cause loss (set to 0.01% as default in
    /// the Vault implementation), so the divested amount might actually be different from
    /// the requested `shares` to divest
    /// @dev care should be taken, as the `shares` parameter is *not* in terms of underlying,
    /// but in terms of yvault shares
    /// @return withdrawn the total amount divested, in terms of underlying asset
    function _divest(uint256 shares) internal override returns (uint256 withdrawn) {
        // return uint256 withdrawn = yVault.withdraw(shares);
        assembly {
            // store selector and parameters in memory
            mstore(0x00, 0x2e1a7d4d)
            mstore(0x20, shares)
            // call yVault.withdraw(shares)
            if iszero(call(gas(), sload(yVault.slot), 0, 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            withdrawn := mload(0x00)
        }

        // swap the LUSD to USDC
        router.exactInputSingle(
            IRouter.ExactInputSingleParams({
                tokenIn: lusd,
                tokenOut: underlyingAsset,
                fee: 500,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: withdrawn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        withdrawn = _lusdBalance();

        assembly {
            // Emit the `Divested` event
            mstore(0x00, shares)
            mstore(0x20, withdrawn)
            log2(0x00, 0x40, _DIVESTED_EVENT_SIGNATURE, address())
        }
    }

    /// @notice Performs any adjustments to the core position(s) of this Strategy given
    /// what change the MaxApy Vault made in the "investable capital" available to the
    /// Strategy.
    /// @dev Note that all "free capital" (capital not invested) in the Strategy after the report
    /// was made is available for reinvestment. This number could be 0, and this scenario should be handled accordingly.
    function _adjustPosition(uint256, uint256 minOutputAfterInvestment) internal override {
        uint256 toInvest = _underlyingBalance();
        if (toInvest > minSingleTrade && toInvest < maxSingleTrade) {
            _invest(toInvest, minOutputAfterInvestment);
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Determines the current value of `shares`.
    /// @dev if sqrt(yVault.totalAssets()) >>> 1e39, this could potentially revert
    /// @return returns the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view override returns (uint256) {
        uint256 vaultTotalSupply;
        assembly {
            // get yVault.totalSupply()
            mstore(0x00, 0x18160ddd)
            if iszero(staticcall(gas(), sload(yVault.slot), 0x1c, 0x04, 0x00, 0x20)) { revert(0x00, 0x04) }
            vaultTotalSupply := mload(0x00)
        }
        if (vaultTotalSupply == 0) return shares;

        uint256 lusdValue = Math.mulDiv(shares, _freeFunds(), vaultTotalSupply);
        // estimate USDC value of the LUSD tokens
        return _estimateAmountOut(lusd, underlyingAsset, uint128(lusdValue), 10);
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return shares returns the estimated amount of shares computed in exchange for underlying `amount`
    function _sharesForAmount(uint256 amount) internal view override returns (uint256 shares) {
        // estimate the LUSD value of the underlying amount
        amount = _estimateAmountOut(
            underlyingAsset,
            lusd,
            uint128(amount), 
            10
        ); 
        uint256 freeFunds = _freeFunds();
        assembly {
            // if freeFunds != 0 return amount
            if gt(freeFunds, 0) {
                // get yVault.totalSupply()
                mstore(0x00, 0x18160ddd)
                if iszero(staticcall(gas(), sload(yVault.slot), 0x1c, 0x04, 0x00, 0x20)) { revert(0x00, 0x04) }
                let totalSupply := mload(0x00)

                // Overflow check equivalent to require(totalSupply == 0 || amount <= type(uint256).max / totalSupply)
                if iszero(iszero(mul(totalSupply, gt(amount, div(not(0), totalSupply))))) { revert(0, 0) }

                shares := div(mul(amount, totalSupply), freeFunds)
            }
        }
    }

    /// @notice Returns the LUSD token balane of the strategy
    /// @return The amount of LUSD tokens held by the current contract
    function _lusdBalance() internal view returns (uint256) {
        return lusd.balanceOf(address(this));
    }

    /// @notice returns the estimated result of a Uniswap V3 swap
    function _estimateAmountOut(address tokenIn, address tokenOut, uint128 amountIn, uint32 secondsAgo)
        internal
        view
        returns (uint256 amountOut)
    {
        
        // Code copied from OracleLibrary.sol, consult()
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        // int56 since tick * time = int24 * uint32
        // 56 = 24 + 32
        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        // int56 / uint32 = int24
        int24 tick = int24(int256(tickCumulativesDelta) / int256(int32(secondsAgo)));
        // Always round to negative infinity

        if (tickCumulativesDelta < 0 && (int256(tickCumulativesDelta) % int256(int32(secondsAgo)) != 0)) {
            tick--;
        }

        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
    }
}
