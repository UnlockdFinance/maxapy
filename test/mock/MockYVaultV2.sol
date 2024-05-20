// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { MockERC20 } from "../../lib/solady/test/utils/mocks/MockERC20.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract MockYVaultV2 is MockERC20 {
    using SafeTransferLib for address;
    ////////////////////////////////////////////////////////////////
    ///                         CONSTANTS                        ///
    ////////////////////////////////////////////////////////////////

    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant DEGRADATION_COEFFICIENT = 1e18;

    /// @notice block.timestamp of last report
    uint256 public lastReport;
    /// @notice How much profit is locked and cant be withdrawn
    uint256 public lockedProfit;
    /// @notice Rate per block of degradation. DEGRADATION_COEFFICIENT is 100% per block
    uint256 public lockedProfitDegradation;

    address asset;

    constructor(address underlying_, string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {
        asset = underlying_;
        lastReport = block.timestamp;
        lockedProfitDegradation = (DEGRADATION_COEFFICIENT * 46) / 10 ** 6; // 6 hours in blocks
    }

    function deposit(uint256 amount) external returns (uint256) {
        uint256 vaultTotalSupply = totalSupply();
        uint256 shares = amount;
        /// By default minting 1:1 shares

        if (vaultTotalSupply != 0) {
            /// Mint amount of tokens based on what the Vault is managing overall
            shares = (amount * vaultTotalSupply) / _freeFunds();
        }
        _mint(msg.sender, shares);
        return shares;
    }

    function withdraw(uint256 shares, address recipient, uint256 maxLoss) external returns (uint256) {
        assembly ("memory-safe") {
            // if maxLoss > MAX_BPS
            if gt(maxLoss, MAX_BPS) {
                // throw the `InvalidMaxLoss` error
                mstore(0x00, 0xef374dc7)
                revert(0x1c, 0x04)
            }

            // if shares == 0
            if iszero(shares) {
                // throw the `InvalidZeroShares` error
                mstore(0x00, 0x5a870a25)
                revert(0x1c, 0x04)
            }

            // if (shares == type(uint256).max) shares = balanceOf(msg.sender);
            if eq(shares, not(0)) {
                // compute `balanceOf(msg.sender)` and store it in `shares`
                mstore(0x0c, 0x87a211a2) // `_BALANCE_SLOT_SEED`
                mstore(0x00, caller())
                shares := sload(keccak256(0x0c, 0x20))
            }
        }

        uint256 valueToWithdraw = _shareValue(shares);
        asset.safeTransfer(recipient, valueToWithdraw);
    }

    function totalAssets() external view returns(uint256) {
        return _totalAssets();
    }

    function _shareValue(uint256 shares) internal view returns (uint256 shareValue) {
        uint256 totalSupply_ = totalSupply();
        // Return price = 1:1 if vault is empty
        if (totalSupply_ == 0) return shares;
        uint256 freeFunds = _freeFunds();
        assembly {
            // Overflow check equivalent to require(freeFunds == 0 || shares <= type(uint256).max / freeFunds)
            if iszero(iszero(mul(freeFunds, gt(shares, div(not(0), freeFunds))))) { revert(0, 0) }
            // shares * freeFunds / totalSupply_
            shareValue := div(mul(shares, freeFunds), totalSupply_)
        }
    }

    function _freeFunds() internal view returns (uint256) {
        return _totalAssets() - _calculateLockedProfit();
    }

    function _totalAssets() internal view returns (uint256 totalAssets) {
        return asset.balanceOf(address(this));
    }

    function _calculateLockedProfit() internal view returns (uint256 calculatedLockedProfit) {
        assembly {
            // No need to check for underflow, since block.timestamp is always greater or equal than lastReport
            let difference := sub(timestamp(), sload(lastReport.slot)) // difference = block.timestamp - lastReport
            let lockedProfitDegradation_ := sload(lockedProfitDegradation.slot)

            // Overflow check equivalent to require(lockedProfitDegradation_ == 0 || difference <= type(uint256).max /
            // lockedProfitDegradation_)
            if iszero(iszero(mul(lockedProfitDegradation_, gt(difference, div(not(0), lockedProfitDegradation_))))) {
                revert(0, 0)
            }

            // lockedFundsRatio = (block.timestamp - lastReport) * lockedProfitDegradation
            let lockedFundsRatio := mul(difference, lockedProfitDegradation_)

            if lt(lockedFundsRatio, DEGRADATION_COEFFICIENT) {
                let vaultLockedProfit := sload(lockedProfit.slot)
                // Overflow check equivalent to require(vaultLockedProfit == 0 || lockedFundsRatio <= type(uint256).max
                // / vaultLockedProfit)
                if iszero(iszero(mul(vaultLockedProfit, gt(lockedFundsRatio, div(not(0), vaultLockedProfit))))) {
                    revert(0, 0)
                }
                // ((lockedFundsRatio * vaultLockedProfit) / DEGRADATION_COEFFICIENT
                let degradation := div(mul(lockedFundsRatio, vaultLockedProfit), DEGRADATION_COEFFICIENT)
                // Overflow check
                if gt(degradation, vaultLockedProfit) { revert(0, 0) }
                // calculatedLockedProfit = vaultLockedProfit - ((lockedFundsRatio * vaultLockedProfit) /
                // DEGRADATION_COEFFICIENT);
                calculatedLockedProfit := sub(vaultLockedProfit, degradation)
            }
        }
    }
}
