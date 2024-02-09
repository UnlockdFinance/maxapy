// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {BaseStrategy, IERC20, IMaxApyVaultV2, SafeTransferLib} from "../base/BaseStrategy.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {ICellar} from "../../interfaces/ICellar.sol";

import {FixedPointMathLib as Math} from "solady/utils/FixedPointMathLib.sol";

/// @title SommelierRealYieldUSDStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/Strategy.sol
/// @notice `SommelierRealYieldUSDStrategy` supplies an underlying token into a generic Sommelier Vault,
/// earning the Sommelier Vault's yield
contract SommelierRealYieldUSDStrategy is BaseStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                         ERRORS                           ///
    ////////////////////////////////////////////////////////////////
    error NotEnoughFundsToInvest();
    error MinOutputAmountNotReached();
    error SharesLocked();
    error HarvestTimeNotElapsed();

    ////////////////////////////////////////////////////////////////
    ///                         EVENTS                           ///
    ////////////////////////////////////////////////////////////////

    /// @notice Emitted when underlying asset is deposited into the Sommelier Vault
    event Invested(address indexed strategy, uint256 amountInvested);

    /// @notice Emitted when the `requestedShares` are divested from the Sommelier Vault
    event Divested(address indexed strategy, uint256 requestedShares, uint256 amountDivested);

    // @dev `keccak256(bytes("Invested(uint256,uint256)"))`.
    uint256 internal constant _INVESTED_EVENT_SIGNATURE =
        0xc3f75dfc78f6efac88ad5abb5e606276b903647d97b2a62a1ef89840a658bbc3;

    // @dev `keccak256(bytes("Divested(uint256,uint256,uint256)"))`.
    uint256 internal constant _DIVESTED_EVENT_SIGNATURE =
        0xf44b6ecb6421462dee6400bd4e3bb57864c0f428d0f7e7d49771f9fd7c30d4fa;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////

    /// @notice The Sommelier Vault the strategy interacts with
    ICellar public cellar;
    /// @notice Timestamp of the last harvest
    uint256 public lastHarvest;
    /// @notice 3 days delay between harvests
    uint256 public constant HARVEST_INTERVAL = 259200; // 3 days

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer {}

    /// @notice Initialize a new Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be granted the keeper role
    /// @param _strategyName the name of the strategy
    function __BaseStrategy_init(
        IMaxApyVaultV2 _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist
    ) internal override onlyInitializing {
        assembly ("memory-safe") {
            // Ensure `_strategist` address is != from address(0)
            if eq(_strategist, 0) {
                // throw the `InvalidZeroAddress` error
                mstore(0x00, 0xf6b2911f)
                revert(0x1c, 0x04)
            }
        }

        vault = _vault;
        _grantRoles(address(_vault), VAULT_ROLE);

        // Cache underlying asset
        (bool success, bytes memory data) = address(_vault).staticcall(abi.encodeWithSignature("asset()"));
        require(success, "asset");
        address _underlyingAsset = abi.decode(data, (address));

        underlyingAsset = _underlyingAsset;

        // Approve MaxApyVault to transfer underlying
        _underlyingAsset.safeApprove(address(_vault), type(uint256).max);

        // Grant keepers with `KEEPER_ROLE`
        for (uint256 i; i < _keepers.length;) {
            _grantRoles(_keepers[i], KEEPER_ROLE);
            unchecked {
                ++i;
            }
        }

        // Set caller as admin and owner
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, ADMIN_ROLE);

        strategyName = _strategyName;

        emergencyExit = 1;

        strategist = _strategist;
        lastHarvest = block.timestamp;
    }

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _cellar The address of the Sommelier Turbo-stETH cellar
    function initialize(
        IMaxApyVaultV2 _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        ICellar _cellar
    ) public initializer {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        cellar = _cellar;
        /// Approve Cellar Vault to transfer underlying
        /// Ensure first approval is 0 to pass USDC race condition
        underlyingAsset.safeApprove(address(_cellar), 0);
        underlyingAsset.safeApprove(address(_cellar), type(uint256).max);
    }

    /////////////////////////////////////////////////////////////////
    ///                    VIEW FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice Provide an accurate estimate for the total amount of assets
    /// (principle + return) that this Strategy is currently managing,
    /// denominated in terms of `underlyingAsset` tokens.
    /// This total should be "realizable" e.g. the total value that could
    /// *actually* be obtained from this Strategy if it were to divest its
    /// entire position based on current on-chain conditions.
    /// @dev Care must be taken in using this function, since it relies on external
    /// systems, which could be manipulated by the attacker to give an inflated
    /// (or reduced) value produced by this function, based on current on-chain
    /// conditions (e.g. this function is possible to influence through
    /// flashloan attacks, oracle manipulations, or other DeFi attack
    /// mechanisms).
    /// @return The estimated total assets in this Strategy.
    function estimatedTotalAssets() public view returns (uint256) {
        // always try to use the value from the last harvest so share price dont fluctuate too much
        // always be pessimistic, take the lowest between the last harvest assets and assets in that moment
        return Math.min(lastEstimatedTotalAssets,_estimatedTotalAssets());
    }

    /// @notice Provides an indication of whether this strategy is currently "active"
    /// in that it is managing an active position, or will manage a position in
    /// the future. This should correlate to `harvest()` activity, so that Harvest
    /// events can be tracked externally by indexing agents.
    /// @return True if the strategy is actively managing a position.
    function isActive() public view returns (bool) {
        return estimatedTotalAssets() != 0;
    }

    /// @notice This function is meant to be called from the vault
    /// @dev calculates the real output of a withdrawal(including losses) for a @param requestedAmount
    /// for the vault to be able to provide an accurate amount when calling either
    ///`previewWithdraw` or `previewRedeem`
    /// @return liquidatedAmount output in assets
    function previewWithdraw(uint256 requestedAmount) public view returns (uint256 liquidatedAmount) {
        if (cellar.userShareLockStartTime(address(this)) + cellar.shareLockPeriod() > block.timestamp) {
            return 0;
        }
        uint256 loss;
        uint256 underlyingBalance = _underlyingBalance();
        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the Cellar Vault
        if (underlyingBalance < requestedAmount) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = requestedAmount - underlyingBalance;
            }
            uint256 shares = _sharesForAmount(amountToWithdraw);
            uint256 withdrawn = cellar.previewRedeem(shares);
            if (withdrawn < amountToWithdraw) loss = amountToWithdraw - withdrawn;
        }
        liquidatedAmount = requestedAmount - loss;
    }

    function previewWithdrawRequest(uint256 liquidatedAmount) public view returns (uint256 requestedAmount) {
        if (cellar.userShareLockStartTime(address(this)) + cellar.shareLockPeriod() > block.timestamp) {
            return 0;
        }
        uint256 underlyingBalance = _underlyingBalance();
        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the Cellar Vault
        if (underlyingBalance < liquidatedAmount) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = liquidatedAmount - underlyingBalance;
            }
            uint256 requestedShares = cellar.previewMint(amountToWithdraw);
            requestedAmount = _shareValue(requestedShares);
        }
        requestedAmount = underlyingBalance + requestedAmount;
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice The Sommelier `Real Yield USD` strategy requires that 24h have elapsed
    /// since the last deposit. This function ensures the condition is met before performin
    /// any other action

    function _checkIfSharesLocked() internal view {
        uint256 sharesUnlockedTimestamp = cellar.userShareLockStartTime(address(this)) + cellar.shareLockPeriod();
        if (sharesUnlockedTimestamp > block.timestamp) {
            revert SharesLocked();
        }
    }

    /// @notice Perform any Strategy unwinding or other calls necessary to capture the
    /// "free return" this Strategy has generated since the last time its core
    /// position(s) were adjusted. Examples include unwrapping extra rewards.
    /// This call is only used during "normal operation" of a Strategy, and
    /// should be optimized to minimize losses as much as possible.
    /// @dev This method returns any realized profits and/or realized losses
    /// incurred, and should return the total amounts of profits/losses/debt
    /// payments (in MaxApy Vault's `underlyingAsset` tokens) for the MaxApy Vault's accounting (e.g.
    /// `underlyingAsset.balanceOf(this) >= debtPayment + profit`).
    ///
    /// `debtOutstanding` will be 0 if the Strategy is not past the configured
    /// debt limit, otherwise its value will be how far past the debt limit
    /// the Strategy is. The Strategy's debt limit is configured in the MaxApy Vault.
    ///
    /// NOTE: `debtPayment` should be less than or equal to `debtOutstanding`.
    ///       It is okay for it to be less than `debtOutstanding`, as that
    ///       should only be used as a guide for how much is left to pay back.
    ///       Payments should be made to minimize loss from slippage, debt,
    ///       withdrawal fees, etc.
    /// NOTE: It must check shareas are unlocked before liquidation the positions
    /// See `MaxApcellar.debtOutstanding()`.
    function _prepareReturn(uint256 debtOutstanding, uint256)
        internal
        override
        returns (uint256 profit, uint256 loss, uint256 debtPayment)
    {
        _checkIfSharesLocked();
        if (block.timestamp < lastHarvest + HARVEST_INTERVAL) {
            revert HarvestTimeNotElapsed();
        }
        lastHarvest = block.timestamp;
        // Fetch initial strategy state
        uint256 underlyingBalance = _underlyingBalance();
        uint256 shares = _shareBalance();
        uint256 totalAssets = underlyingBalance + _shareValue(shares);

        uint256 debt;
        assembly {
            // debt = vault.strategies(address(this)).strategyTotalDebt;
            mstore(0x00, 0xbdb9f8b3)
            mstore(0x20, address())
            if iszero(call(gas(), sload(vault.slot), 0, 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            debt := mload(0x00)
        }

        if (totalAssets >= debt) {
            // Strategy has obtained profit or holds more funds than it should
            // considering the current debt
            profit = totalAssets - debt;

            uint256 amountToWithdraw = profit + debtOutstanding;

            // Check if underlying funds held in the strategy are enough to cover withdrawal.
            // If not, divest from Cellar
            if (amountToWithdraw > underlyingBalance) {
                uint256 expectedAmountToWithdraw = amountToWithdraw - underlyingBalance;

                uint256 sharesToWithdraw = _sharesForAmount(expectedAmountToWithdraw);

                uint256 withdrawn = _divest(sharesToWithdraw);

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
                // Net off profit and loss
                switch lt(profit, loss)
                // if (profit < loss)
                case true {
                    loss := sub(loss, profit)
                    profit := 0
                }
                case false {
                    profit := sub(profit, loss)
                    loss := 0
                }
            }
            // `profit` + `debtOutstanding` must be <= `underlyingBalance`. Prioritise profit first
            if (profit > underlyingBalance) {
                // Profit is prioritised. In this case, no `debtPayment` will be reported
                profit = underlyingBalance;
            } else if (amountToWithdraw > underlyingBalance) {
                // same as `profit` + `debtOutstanding` > `underlyingBalance`
                // Extract debt payment from divested amount
                unchecked {
                    debtPayment = underlyingBalance - profit;
                }
            } else {
                debtPayment = debtOutstanding;
            }
        } else {
            assembly {
                loss := sub(debt, totalAssets)
            }
        }
    }

    /// TODO:doc
    function _prepareReturn(uint256 debtOutstanding, uint256, uint256 harvestedProfitBPS)
        internal
        override
        returns (uint256 profit, uint256 loss, uint256 debtPayment)
    {   
        /// if we are not realizing any profit we can bypass the withdraw constrains
        if(harvestedProfitBPS > 0) {
            _checkIfSharesLocked();
            if (block.timestamp < lastHarvest + HARVEST_INTERVAL) {
                revert HarvestTimeNotElapsed();
            }
            lastHarvest = block.timestamp;
        }
        // Fetch initial strategy state
        uint256 underlyingBalance = _underlyingBalance();
        uint256 shares = _shareBalance();
        uint256 totalAssets = underlyingBalance + _shareValue(shares);

        uint256 debt;
        assembly {
            // debt = vault.strategies(address(this)).strategyTotalDebt;
            mstore(0x00, 0xbdb9f8b3)
            mstore(0x20, address())
            if iszero(call(gas(), sload(vault.slot), 0, 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            debt := mload(0x00)
        }

        if (totalAssets >= debt) {
            // Strategy has obtained profit or holds more funds than it should
            // considering the current debt

            // we will report harvestedProfitBPS % of the profits only so we can compound the rest
            profit = Math.fullMulDiv(totalAssets - debt, harvestedProfitBPS, MAX_BPS);


            uint256 amountToWithdraw = profit + debtOutstanding;

            // Check if underlying funds held in the strategy are enough to cover withdrawal.
            // If not, divest from Cellar
            if (amountToWithdraw > underlyingBalance) {
                uint256 expectedAmountToWithdraw = amountToWithdraw - underlyingBalance;

                uint256 sharesToWithdraw = _sharesForAmount(expectedAmountToWithdraw);

                uint256 withdrawn = _divest(sharesToWithdraw);

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
                // Net off profit and loss
                switch lt(profit, loss)
                // if (profit < loss)
                case true {
                    loss := sub(loss, profit)
                    profit := 0
                }
                case false {
                    profit := sub(profit, loss)
                    loss := 0
                }
            }
            // `profit` + `debtOutstanding` must be <= `underlyingBalance`. Prioritise profit first
            if (profit > underlyingBalance) {
                // Profit is prioritised. In this case, no `debtPayment` will be reported
                profit = underlyingBalance;
            } else if (amountToWithdraw > underlyingBalance) {
                // same as `profit` + `debtOutstanding` > `underlyingBalance`
                // Extract debt payment from divested amount
                unchecked {
                    debtPayment = underlyingBalance - profit;
                }
            } else {
                debtPayment = debtOutstanding;
            }
        } else {
            assembly {
                loss := sub(debt, totalAssets)
            }
        }
    }

    /// @notice Performs any adjustments to the core position(s) of this Strategy given
    /// what change the MaxApy Vault made in the "investable capital" available to the
    /// Strategy.
    /// @dev Note that all "free capital" (capital not invested) in the Strategy after the report
    /// was made is available for reinvestment. This number could be 0, and this scenario should be handled accordingly.
    function _adjustPosition(uint256, uint256 minOutputAfterInvestment) internal override {
        uint256 toInvest = _underlyingBalance();
        _invest(toInvest, minOutputAfterInvestment);
    }

    /// @notice Invests `amount` of underlying, depositing it in the Cellar Vault
    /// @param amount The amount of underlying to be deposited in the vault
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Cellar receipt tokens)
    /// @return depositedAmount The amount of shares received, in terms of underlying
    function _invest(uint256 amount, uint256 minOutputAfterInvestment) internal returns (uint256 depositedAmount) {
        // Don't do anything if amount to invest is 0
        if (amount == 0) return 0;

        uint256 underlyingBalance = _underlyingBalance();
        if (amount > underlyingBalance) revert NotEnoughFundsToInvest();

        uint256 shares = cellar.deposit(amount, address(this));

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

    /// @notice Divests amount `shares` from Cellar Vault
    /// Note that divesting from Cellar could potentially cause loss (set to 0.01% as default in
    /// the Vault implementation), so the divested amount might actually be different from
    /// the requested `shares` to divest
    /// @dev care should be taken, as the `shares` parameter is *not* in terms of underlying,
    /// but in terms of cellar shares
    /// @return withdrawn the total amount divested, in terms of underlying asset
    function _divest(uint256 shares) internal returns (uint256 withdrawn) {
        withdrawn = cellar.redeem(shares, address(this), address(this));
        emit Divested(address(this), shares, withdrawn);
    }

    /// @notice Liquidate up to `amountNeeded` of MaxApy Vault's `underlyingAsset` of this strategy's positions,
    /// irregardless of slippage. Any excess will be re-invested with `_adjustPosition()`.
    /// @dev This function should return the amount of MaxApy Vault's `underlyingAsset` tokens made available by the
    /// liquidation. If there is a difference between `amountNeeded` and `liquidatedAmount`, `loss` indicates whether the
    /// difference is due to a realized loss, or if there is some other sitution at play
    /// (e.g. locked funds) where the amount made available is less than what is needed.
    /// NOTE: The invariant `liquidatedAmount + loss <= amountNeeded` should always be maintained
    /// @param amountNeeded amount of MaxApy Vault's `underlyingAsset` needed to be liquidated
    /// @return liquidatedAmount the actual liquidated amount
    /// @return loss difference between the expected amount needed to reach `amountNeeded` and the actual liquidated amount
    function _liquidatePosition(uint256 amountNeeded)
        internal
        override
        returns (uint256 liquidatedAmount, uint256 loss)
    {
        if (cellar.userShareLockStartTime(address(this)) + cellar.shareLockPeriod() > block.timestamp) {
            return (0, 0);
        }
        uint256 underlyingBalance = _underlyingBalance();
        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the Cellar Vault
        if (underlyingBalance < amountNeeded) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = amountNeeded - underlyingBalance;
            }
            uint256 shares = _sharesForAmount(amountToWithdraw);
            uint256 withdrawn = _divest(shares);
            assembly {
                // if withdrawn < amountToWithdraw
                if lt(withdrawn, amountToWithdraw) { loss := sub(amountToWithdraw, withdrawn) }
            }
        }
        // liquidatedAmount = amountNeeded - loss;
        assembly {
            liquidatedAmount := sub(amountNeeded, loss)
        }
    }

    /// @notice Liquidates everything and returns the amount that got freed.
    /// @dev This function is used during emergency exit instead of `_prepareReturn()` to
    /// liquidate all of the Strategy's positions back to the MaxApy Vault.
    /// NOTE: It must check shareas are unlocked before liquidation the positions
    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        _checkIfSharesLocked();
        _divest(_shareBalance());
        amountFreed = _underlyingBalance();
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Determines value in assets of a amount of @param shares
    /// @dev fetches directly from ERC4626 `convertToAssets` of Sommelier `Cellar` vault
    /// @return returns the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view returns (uint256) {
        return cellar.convertToAssets(shares);
    }

    /// @notice Determines value in shares of a @param amount of assets
    /// @dev fetches directly from ERC4626 `convertToAShares` of Sommelier `Cellar` vault
    /// @return shares returns the estimated amount of shares computed in exchange for underlying `amount`
    function _sharesForAmount(uint256 amount) internal view returns (uint256 shares) {
        return cellar.convertToShares(amount);
    }

    /// @notice Returns the current strategy's amount of Cellar vault shares
    /// @return _balance balance the strategy's balance of Cellar vault shares
    function _shareBalance() internal view returns (uint256 _balance) {
        return cellar.balanceOf(address(this));
    }

    /// @notice Returns the real time estimation of the value in assets held by the strategy
    /// @return the strategy's total assets(idle + investment positions)
    function _estimatedTotalAssets() internal override view returns (uint256) {
        return _underlyingBalance() + _shareValue(_shareBalance());
    }
}
