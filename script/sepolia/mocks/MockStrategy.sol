// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseStrategy, SafeTransferLib, IMaxApyVaultV2} from "src/strategies/base/BaseStrategy.sol";

contract MockStrategy is BaseStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer {}

    /// @dev the initialization function must be defined in each strategy

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    function initialize(
        IMaxApyVaultV2 _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist
    ) public virtual initializer {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
    }

    function previewLiquidate(uint256 requestedAmount) public view virtual override returns (uint256 liquidatedAmount) {
        liquidatedAmount = requestedAmount;
    }

    function previewLiquidateExact(uint256 liquidatedAmount)
        public
        view
        virtual
        override
        returns (uint256 requestedAmount)
    {
       requestedAmount = liquidatedAmount;
    }

    function maxLiquidate() public view virtual override returns (uint256) {
        return _estimatedTotalAssets();
    }

    function maxLiquidateExact() public view virtual override returns (uint256) {
        // only can request harvested assets
        return _underlyingBalance();
    }
     
    function _adjustPosition(
        uint256 debtOutstanding,
        uint256 minOutputAfterInvestment
    ) internal virtual override {}

    function _liquidatePosition(
        uint256 amountNeeded
    )
        internal
        virtual
        override
        returns (uint256 liquidatedAmount, uint256 loss)
    {
        liquidatedAmount = amountNeeded;
        loss = 0;
    }

    function _liquidateAllPositions()
        internal
        virtual
        override
        returns (uint256 amountFreed)
    {
        amountFreed = underlyingAsset.balanceOf(address(this));
    }

    function _prepareReturn(
        uint256 debtOutstanding,
        uint256 minExpectedBalance,
        uint256 harvestedProfitBPS
    )
        internal
        virtual
        override
        returns (
            uint256 realizedProfit,
            uint256 unrealizedProfit,
            uint256 loss,
            uint256 debtPayment
        )
    {
        
        // Fetch initial strategy state
        uint256 underlyingBalance = _underlyingBalance();
        uint256 _estimatedTotalAssets_ = _estimatedTotalAssets();
        uint256 _lastEstimatedTotalAssets = lastEstimatedTotalAssets;

        uint256 debt;
        assembly {
            // debt = vault.strategies(address(this)).strategyTotalDebt;
            mstore(0x00, 0xd81d5e87)
            mstore(0x20, address())
            if iszero(call(gas(), sload(vault.slot), 0, 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            debt := mload(0x00)
        }

        // initialize the lastEstimatedTotalAssets in case it is not
        if (_lastEstimatedTotalAssets == 0) _lastEstimatedTotalAssets = debt;

        assembly {
            switch lt(_estimatedTotalAssets_, _lastEstimatedTotalAssets)
            // if _estimatedTotalAssets_ < _lastEstimatedTotalAssets
            case true { loss := sub(_lastEstimatedTotalAssets, _estimatedTotalAssets_) }
            // else
            case false { unrealizedProfit := sub(_estimatedTotalAssets_, _lastEstimatedTotalAssets) }
        }

        if (_estimatedTotalAssets_ >= _lastEstimatedTotalAssets) {
            // Strategy has obtained profit or holds more funds than it should
            // considering the current debt

            // we will report harvestedProfitBPS % of the profits only so we can compound the rest
            realizedProfit = unrealizedProfit * harvestedProfitBPS / MAX_BPS;

            uint256 amountToWithdraw = realizedProfit + debtOutstanding;

            // Check if underlying funds held in the strategy are enough to cover withdrawal.
            // If not, divest from Cellar
            if (amountToWithdraw > underlyingBalance) {
                uint256 expectedAmountToWithdraw = amountToWithdraw - underlyingBalance;
                
                uint256 withdrawn = expectedAmountToWithdraw;

                // Account for loss occured on withdrawal from Cellar
                if (withdrawn < expectedAmountToWithdraw) {
                    unchecked {
                        loss = expectedAmountToWithdraw - withdrawn;
                    }
                }
                // Overwrite underlyingBalance with the proper amount after withdrawing
                underlyingBalance = _underlyingBalance();
            }

            assembly {
                // Net off realized profit and loss
                switch lt(realizedProfit, loss)
                // if (realizedProfit < loss)
                case true {
                    loss := sub(loss, realizedProfit)
                    realizedProfit := 0
                }
                case false {
                    realizedProfit := sub(realizedProfit, loss)
                    loss := 0
                }

                // Net off unrealized profit and loss
                switch lt(unrealizedProfit, loss)
                // if (unrealizedProfit < loss)
                case true { realizedProfit := 0 }
                case false {
                    unrealizedProfit := sub(unrealizedProfit, loss)
                    loss := 0
                }
            }
            // `profit` + `debtOutstanding` must be <= `underlyingBalance`. Prioritise profit first
            if (realizedProfit > underlyingBalance) {
                // Profit is prioritised. In this case, no `debtPayment` will be reported
                realizedProfit = underlyingBalance;
            } else if (amountToWithdraw > underlyingBalance) {
                // same as `profit` + `debtOutstanding` > `underlyingBalance`
                // Extract debt payment from divested amount
                unchecked {
                    debtPayment = underlyingBalance - realizedProfit;
                }
            } else {
                debtPayment = debtOutstanding;
            }
        }
    }

    function _estimatedTotalAssets()
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return underlyingAsset.balanceOf(address(this));
    }

    /// @dev simulate strategy gains
    function gain(uint256 amount) external {
        (bool success,) = underlyingAsset.call(abi.encodeWithSignature("mint(address,uint256)", address(this), amount));
        success;
    }

}

