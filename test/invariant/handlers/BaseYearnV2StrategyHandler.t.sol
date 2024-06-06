// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseHandler, console } from "./base/BaseHandler.t.sol";
import { AddressSet, LibAddressSet } from "../../helpers/AddressSet.sol";
import { BaseYearnV2StrategyWrapper } from "../../mock/BaseYearnV2StrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { MockERC20 } from "../../mock/MockERC20.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { BaseStrategyHandler } from "./base/BaseStrategyHandler.t.sol";

contract BaseYearnV2StrategyHandler is BaseStrategyHandler {
    MaxApyVault vault;
    BaseYearnV2StrategyWrapper strategy;
    MockERC20 token;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////
    constructor(MaxApyVault _vault, BaseYearnV2StrategyWrapper _strategy, MockERC20 _token) {
        strategy = _strategy;
        token = _token;
        vault = _vault;
    }

    ////////////////////////////////////////////////////////////////
    ///                      ENTRY POINTS                        ///
    ////////////////////////////////////////////////////////////////
    function gain(uint256 amount) public override countCall("gain") {
        if (currentActor == address(0)) return; // for some reason this caused bugs
        amount = bound(amount, 0, 1000 ether);
        deal(address(token), address(strategy), amount);
        strategy.harvest(0, 0, address(0), block.timestamp);
    }

    function triggerLoss(uint256 amount, bool useLiquidateExact) public override countCall("triggerLoss") {
        uint256 maxLiquidation = strategy.shareValue(strategy.shareBalance());
        if (!useLiquidateExact) {
            amount = bound(amount, 0, maxLiquidation);
            if (amount == 0) return;
            uint256 liquidatePreview = strategy.previewLiquidate(amount);
            uint256 loss = strategy.liquidate(amount);
            assertGe(loss, amount - liquidatePreview);
            expectedEstimatedTotalAssets =
                _sub0(_sub0(strategy.estimatedTotalAssets(), amount), vault.debtOutstanding(address(strategy)));
        } else {
            amount = bound(amount, 0, maxLiquidation * 90 / 100);
            if (amount == 0) return;
            uint256 strategyPreview = strategy.previewLiquidateExact(amount);
            uint256 loss = strategy.liquidateExact(amount);
            assertGe(strategyPreview, amount + loss);
            expectedEstimatedTotalAssets = _sub0(strategy.estimatedTotalAssets(), amount + loss);
        }
        strategy.harvest(0, 0, address(0), block.timestamp);
        actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
    }

    function harvest() public override countCall("harvest") {
        int256 unharvestedAmount = strategy.unharvestedAmount();
        if (unharvestedAmount < 0) {
            expectedEstimatedTotalAssets = strategy.estimatedTotalAssets();
            strategy.harvest(0, 0, address(0), block.timestamp);
            actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
        }

        if (unharvestedAmount > 0) {
            expectedEstimatedTotalAssets = _sub0(
                _sub0(
                    strategy.estimatedTotalAssets() + uint256(strategy.unharvestedAmount()),
                    vault.debtOutstanding(address(strategy))
                ),
                vault.debtOutstanding(address(strategy))
            );
            strategy.harvest(0, 0, address(0), block.timestamp);
            actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                      INVARIANTS                          ///
    ////////////////////////////////////////////////////////////////
    function INVARIANT_A_ESTIMATED_TOTAL_ASSETS() public view override {
        assertGe(expectedEstimatedTotalAssets, actualEstimatedTotalAssets);
    }
}
