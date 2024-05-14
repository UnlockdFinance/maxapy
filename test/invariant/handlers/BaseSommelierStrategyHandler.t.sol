// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseHandler, console } from "./base/BaseHadler.t.sol";
import { AddressSet, LibAddressSet } from "../../helpers/AddressSet.sol";
import { BaseSommelierStrategyWrapper } from "../../mock/BaseSommelierStrategyWrapper.sol";
import { MaxApyVaultV2 } from "src/MaxApyVaultV2.sol";
import { MockERC20 } from "../../mock/MockERC20.sol";

contract BaseSommelierStrategyHandler is BaseHandler {
    MaxApyVaultV2 vault;
    BaseSommelierStrategyWrapper strategy;
    MockERC20 token;

    ////////////////////////////////////////////////////////////////
    ///                      GHOST VARIABLES                     ///
    ////////////////////////////////////////////////////////////////
    uint256 public expectedEstimatedTotalAssets;
    uint256 public actualEstimatedTotalAssets;

    uint256 public expectedLastEstimatedTotalAsset;
    uint256 public actualLastEstimatedTotalAsset;

    uint256 public expectedStrategyBalance;
    uint256 public actualStrategyBalance;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////
    constructor(MaxApyVaultV2 _vault, BaseSommelierStrategyWrapper _strategy, MockERC20 _token) {
        strategy = _strategy;
        token = _token;
        vault = _vault;
    }

    function investSommelier(uint256 amount) public countCall("investSommelier") {
        amount = bound(amount, 0, actualStrategyBalance);
        if (amount == 0) return;
        expectedStrategyBalance = actualStrategyBalance - amount;
        strategy.investSommelier(amount);
        actualStrategyBalance = token.balanceOf(address(strategy));
    }

    function triggerLoss(uint256 amount) public countCall("trigerLoss") {
        amount = bound(amount, 0, actualStrategyBalance);
        if (amount == 0) return;
        expectedEstimatedTotalAssets = actualEstimatedTotalAssets - amount;
        expectedStrategyBalance = actualStrategyBalance - amount;
        strategy.triggerLoss(amount);
        actualStrategyBalance = token.balanceOf(address(strategy));
        actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
    }

    function mockReport(uint256 gain, uint256 loss, uint256 debtPayment, address treasury) public countCall("") {
        int256 pnl = strategy.unharvestedAmount();
        if (pnl > 0) {
            gain = bound(gain, 0, uint256(pnl));
            loss = bound(loss, 0, gain + 1);
        } else {
            gain = 0;
            loss = bound(loss, 0, uint256(-pnl));
        }

        debtPayment = bound(debtPayment, 0, vault.getStrategyTotalDebt(address(strategy)));
        strategy.mockReport(uint128(gain), uint128(loss), uint128(debtPayment), treasury);
    }

    function adjustPosition() public countCall("") {
        strategy.adjustPosition();
        ///silence warning
    }

    function invest(uint256 amount, uint256 minOutputAfterInvestment) public countCall("") {
        bound(amount, 0, actualStrategyBalance);
        minOutputAfterInvestment = 0;
        strategy.invest(amount, minOutputAfterInvestment);
    }

    function liquidatePosition(uint256 amountNeeded) public countCall("liquidatePosition") {
        bound(amountNeeded, 0, strategy.maxLiquidate());
        strategy.liquidatePosition(amountNeeded);
    }

    function liquidateAllPositions() public countCall("liquidateAllPositions") {
        strategy.liquidateAllPositions();
    }

    ////////////////////////////////////////////////////////////////
    ///                      HELPERS                             ///
    ////////////////////////////////////////////////////////////////
    function getEntryPoints() public pure override returns (bytes4[] memory) {
        bytes4[] memory _entryPoints = new bytes4[](7);
        _entryPoints[0] = this.investSommelier.selector;
        _entryPoints[1] = this.triggerLoss.selector;
        _entryPoints[2] = this.mockReport.selector;
        _entryPoints[3] = this.adjustPosition.selector;
        _entryPoints[4] = this.invest.selector;
        _entryPoints[5] = this.liquidatePosition.selector;
        _entryPoints[6] = this.liquidateAllPositions.selector;
        return _entryPoints;
    }

    function callSummary() public view override {
        console.log("");
        console.log("");
        console.log("Call summary:");
        console.log("-------------------");
        console.log("investSommelier", calls["investSommelier"]);
        console.log("trigerLoss", calls["trigerLoss"]);
        console.log("mockReport", calls["mockReport"]);
        console.log("adjustPosition", calls["adjustPosition"]);
        console.log("invest", calls["invest"]);
        console.log("liquidatePosition", calls["liquidatePosition"]);
        console.log("liquidateAllPositinos", calls["liquidateAllPositinos"]);
        console.log("-------------------");
    }
}
