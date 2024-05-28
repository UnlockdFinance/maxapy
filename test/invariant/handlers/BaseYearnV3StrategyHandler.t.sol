// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseHandler, console } from "./base/BaseHandler.t.sol";
import { AddressSet, LibAddressSet } from "../../helpers/AddressSet.sol";
import { BaseYearnV3StrategyWrapper } from "../../mock/BaseYearnV3StrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { MockERC20 } from "../../mock/MockERC20.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

contract BaseYearnV3StrategyHandler is BaseHandler {
    MaxApyVault vault;
    BaseYearnV3StrategyWrapper strategy;
    MockERC20 token;

    ////////////////////////////////////////////////////////////////
    ///                      GHOST VARIABLES                     ///
    ////////////////////////////////////////////////////////////////
    uint256 public expectedEstimatedTotalAssets;
    uint256 public actualEstimatedTotalAssets;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////
    constructor(MaxApyVault _vault, BaseYearnV3StrategyWrapper _strategy, MockERC20 _token) {
        strategy = _strategy;
        token = _token;
        vault = _vault;
    }

    ////////////////////////////////////////////////////////////////
    ///                      ENTRY POINTS                        ///
    ////////////////////////////////////////////////////////////////
    function gain(uint256 amount) public countCall("gain") {
        amount = bound(amount, 0, 1_000_000 ether);
        deal(address(token), address(strategy), amount);
        strategy.harvest(0, 0, 0, address(0));
    }

    function triggerLoss(uint256 amount, bool useLiquidateExact) public countCall("triggerLoss") {
        uint256 maxLiquidation = strategy.shareValue(strategy.shareBalance());
        if (!useLiquidateExact) {
            amount = bound(amount, 0, maxLiquidation);
            if (amount == 0) return;
            uint256 liquidatePreview = strategy.previewLiquidate(amount);
            expectedEstimatedTotalAssets = _sub0(strategy.estimatedTotalAssets(), amount);
            uint256 loss = strategy.liquidate(amount);
            assertGe(loss, amount - liquidatePreview);
        } else {
            amount = bound(amount, 0, maxLiquidation * 90 / 100);
            if (amount == 0) return;
            uint256 strategyPreview = strategy.previewLiquidateExact(amount);
            uint256 loss = strategy.liquidateExact(amount);
            assertGe(strategyPreview, amount + loss);
            expectedEstimatedTotalAssets = _sub0(strategy.estimatedTotalAssets(), amount + loss);
        }
        actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
        strategy.harvest(0, 0, 0, address(0));
    }

    function harvest() public countCall("harvest") {
        int256 unharvestedAmount = strategy.unharvestedAmount();
        if (unharvestedAmount < 0) {
            expectedEstimatedTotalAssets = strategy.estimatedTotalAssets();
            strategy.harvest(0, 0, 0, address(0));
            actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
        }

        if (unharvestedAmount > 0) {
            expectedEstimatedTotalAssets = strategy.estimatedTotalAssets() + uint256(strategy.unharvestedAmount());
            strategy.harvest(0, 0, 0, address(0));
            actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                      HELPERS                             ///
    ////////////////////////////////////////////////////////////////
    function getEntryPoints() public pure override returns (bytes4[] memory) {
        bytes4[] memory _entryPoints = new bytes4[](3);
        _entryPoints[0] = this.gain.selector;
        _entryPoints[1] = this.harvest.selector;
        _entryPoints[2] = this.triggerLoss.selector;
        return _entryPoints;
    }

    function callSummary() public view override {
        console.log("");
        console.log("");
        console.log("Call summary:");
        console.log("-------------------");
        console.log("gain", calls["gain"]);
        console.log("trigerLoss", calls["trigerLoss"]);
        console.log("harvest", calls["harvest"]);
        console.log("-------------------");
    }
}
