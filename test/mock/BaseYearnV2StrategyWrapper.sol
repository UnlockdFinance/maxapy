// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseYearnV2Strategy, SafeTransferLib } from "src/strategies/base/BaseYearnV2Strategy.sol";

contract BaseYearnV2StrategyWrapper is BaseYearnV2Strategy {
    using SafeTransferLib for address;

    function investYearn(uint256 amount) external returns (uint256) {
        return yVault.deposit(amount);
    }

    function triggerLoss(uint256 amount) external {
        underlyingAsset.safeTransfer(address(underlyingAsset), amount);
    }

    function mockReport(uint128 gain, uint128 loss, uint128 debtPayment, address treasury) external {
        vault.report(gain, gain, loss, debtPayment, treasury);
    }

    function prepareReturn(
        uint256 debtOutstanding,
        uint256 minExpectedBalance,
        uint256 harvestedProvitBPS
    )
        external
        returns (uint256 realizedProfit, uint256 unrealizedProfit, uint256 loss, uint256 debtPayment)
    {
        (realizedProfit, unrealizedProfit, loss, debtPayment) =
            _prepareReturn(debtOutstanding, minExpectedBalance, harvestedProvitBPS);
    }

    function adjustPosition() external {
        _adjustPosition(0, 0);
        ///silence warning
    }

    function invest(uint256 amount, uint256 minOutputAfterInvestment) external returns (uint256) {
        return _invest(amount, minOutputAfterInvestment);
    }

    function divest(uint256 shares) external returns (uint256) {
        return _divest(shares);
    }

    function liquidatePosition(uint256 amountNeeded) external returns (uint256, uint256) {
        return _liquidatePosition(amountNeeded);
    }

    function liquidateAllPositions() external returns (uint256) {
        return _liquidateAllPositions();
    }

    function shareValue(uint256 shares) external view returns (uint256) {
        return _shareValue(shares);
    }

    function sharesForAmount(uint256 amount) external view returns (uint256) {
        return _sharesForAmount(amount);
    }

    function shareBalance() external view returns (uint256) {
        return _shareBalance();
    }
}
