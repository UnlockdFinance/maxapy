// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    SommelierRealYieldUSDStrategy,
    SafeTransferLib
} from "../../src/strategies/sommelier/SommelierRealYieldUSDStrategy.sol";

contract SommelierRealYieldStrategyWrapper is SommelierRealYieldUSDStrategy {
    using SafeTransferLib for address;

    function investSommelier(uint256 amount) external returns (uint256) {
        return cellar.deposit(amount, address(this));
    }

    function triggerLoss(uint256 amount) external {
        // use address(1) since USDC has blacklisted addresses
        underlyingAsset.safeTransfer(address(1), amount);
    }

    function mockReport(uint128 gain, uint128 loss, uint128 debtPayment) external {
        vault.report(gain, loss, debtPayment);
    }

    function prepareReturn(uint256 debtOutstanding, uint256 minExpectedBalance)
        external
        returns (uint256 profit, uint256 loss, uint256 debtPayment)
    {
        (profit, loss, debtPayment) = _prepareReturn(debtOutstanding, minExpectedBalance);
    }

    function prepareReturn(uint256 debtOutstanding, uint256 minExpectedBalance, uint256 harvestedProvitBPS)
        external
        returns (uint256 profit, uint256 loss, uint256 debtPayment)
    {
        (profit, loss, debtPayment) = _prepareReturn(debtOutstanding, minExpectedBalance,harvestedProvitBPS);
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
