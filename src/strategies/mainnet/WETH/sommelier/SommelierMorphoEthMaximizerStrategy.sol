// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    BaseSommelierStrategy,
    SafeTransferLib,
    IMaxApyVault,
    ICellar
} from "src/strategies/base/BaseSommelierStrategy.sol";
import { IUniswapV3Router } from "src/interfaces/IUniswap.sol";

/// @title SommelierMorphoEthMaximizerStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `SommelierMorphoEthMaximizerStrategy` supplies an underlying token into a generic Sommelier Vault,
/// earning the Sommelier Vault's yield
contract SommelierMorphoEthMaximizerStrategy is BaseSommelierStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                         CONSTANTS                        ///
    ////////////////////////////////////////////////////////////////
    address constant wstEth = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    IUniswapV3Router constant router = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////
    /// @notice Minimun trade size within the strategy
    uint256 public minSingleTrade;
    /// @notice Maximum trade size within the strategy
    uint256 public maxSingleTrade;

    ////////////////////////////////////////////////////////////////
    ///                         EVENTS                           ///
    ////////////////////////////////////////////////////////////////
    /// @notice Emitted when the strategy's min single trade value is updated
    event MinSingleTradeUpdated(uint256 minSingleTrade);

    /// @notice Emitted when the strategy's max single trade value is updated
    event MaxSingleTradeUpdated(uint256 maxSingleTrade);

    /// @dev `keccak256(bytes("MinSingleTradeUpdated(uint256)"))`.
    uint256 internal constant _MIN_SINGLE_TRADE_UPDATED_EVENT_SIGNATURE =
        0x70bc59027d7d0bba6fbf38b995e26c84f6c1805fc3ead71ec1d7ebeb7d76399b;

    /// @dev `keccak256(bytes("MaxSingleTradeUpdated(uint256)"))`.
    uint256 internal constant _MAX_SINGLE_TRADE_UPDATED_EVENT_SIGNATURE =
        0xe8b08f84dc067e4182670384e9556796d3a831058322b7e55f9ddb3ec48d7c10;

    /// @dev the initialization function must be defined in each strategy
    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _cellar The address of the Sommelier Turbo-stETH cellar
    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        ICellar _cellar
    )
        public
        override
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        cellar = _cellar;
        /// Approve Cellar Vault to transfer underlying
        underlyingAsset.safeApprove(address(_cellar), type(uint256).max);
        // Set max and min single trade
        minSingleTrade = 0.001 ether;
        maxSingleTrade = 10 ether;

        // Approve WSETH to router
        wstEth.safeApprove(address(router), type(uint256).max);
    }

    /////////////////////////////////////////////////////////////////
    ///                    CORE LOGIC                             ///
    /////////////////////////////////////////////////////////////////
    /// @notice Withdraws exactly `amountNeeded` to `vault`.
    /// @dev This may only be called by the respective Vault.
    /// @param amountNeeded How much `underlyingAsset` to withdraw.
    /// @return loss Any realized losses
    function liquidateExact(uint256 amountNeeded)
        external
        virtual
        override
        checkRoles(VAULT_ROLE)
        returns (uint256 loss)
    {
        uint256 underlyingBalance = _underlyingBalance();
        if (underlyingBalance < amountNeeded) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = amountNeeded - underlyingBalance;
            }
            uint256 burntShares = cellar.withdraw(amountToWithdraw, address(this), address(this));
            // use sub zero because shares could be fewer than expected and underflow
            loss = _sub0(_shareValue(burntShares), amountToWithdraw);
        }

        uint256 wstEthBalance = _wstEthBalance();
        if (wstEthBalance > 0) _swapWstEth(wstEthBalance);
        underlyingAsset.safeTransfer(address(vault), amountNeeded);
        // Note: Reinvest anything leftover on next `harvest`
        _snapshotEstimatedTotalAssets();
    }
    ////////////////////////////////////////////////////////////////
    ///                 STRATEGY CONFIGURATION                   ///
    ////////////////////////////////////////////////////////////////

    /// @notice Sets the minimum single trade amount allowed
    /// @param _minSingleTrade The new minimum single trade value
    function setMinSingleTrade(uint256 _minSingleTrade) external checkRoles(ADMIN_ROLE) {
        assembly {
            // if _minSingleTrade == 0 revert()
            if iszero(_minSingleTrade) {
                // Throw the `InvalidZeroAmount` error
                mstore(0x00, 0xdd484e70)
                revert(0x1c, 0x04)
            }
            sstore(minSingleTrade.slot, _minSingleTrade)
            // Emit the `MinSingleTradeUpdated` event
            mstore(0x00, _minSingleTrade)
            log1(0x00, 0x20, _MIN_SINGLE_TRADE_UPDATED_EVENT_SIGNATURE)
        }
    }

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

    /// @notice Divests amount `shares` from Cellar Vault
    /// Note that divesting from Cellar could potentially cause loss (set to 0.01% as default in
    /// the Vault implementation), so the divested amount might actually be different from
    /// the requested `shares` to divest
    /// @dev care should be taken, as the `shares` parameter is *not* in terms of underlying,
    /// but in terms of cellar shares
    /// @return withdrawn the total amount divested, in terms of underlying asset
    function _divest(uint256 shares) internal override returns (uint256 withdrawn) {
        // if cellar is paused dont liquidate, skips revert
        if (cellar.isPaused()) return 0;
        uint256 balanceBefore = _underlyingBalance();
        cellar.redeem(shares, address(this), address(this));
        uint256 wstEthBalance = _wstEthBalance();
        if (wstEthBalance > 0) _swapWstEth(wstEthBalance);
        withdrawn = _underlyingBalance() - balanceBefore;
        emit Divested(address(this), shares, withdrawn);
    }

    /// @notice helper function to swap the WSTETH in balance to underlying WETH
    function _swapWstEth(uint256 amountIn) internal returns (uint256) {
        if (amountIn < minSingleTrade) return 0;
        return router.exactInputSingle(
            IUniswapV3Router.ExactInputSingleParams({
                tokenIn: wstEth,
                tokenOut: underlyingAsset,
                fee: 100,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////
    /// @notice returns WSTETH balance
    function _wstEthBalance() internal view returns (uint256) {
        return wstEth.balanceOf(address(this));
    }
}
