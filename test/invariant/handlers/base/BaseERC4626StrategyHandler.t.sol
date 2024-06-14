// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseStrategyHandler } from "./BaseStrategyHandler.t.sol";
import { AddressSet, LibAddressSet } from "../../../helpers/AddressSet.sol";
import { IStrategyWrapper } from "../../../interfaces/IStrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { MockERC20 } from "../../../mock/MockERC20.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

contract BaseERC4626StrategyHandler is BaseStrategyHandler {
    MaxApyVault vault;
    IStrategyWrapper strategy;
    MockERC20 token;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////
    constructor(MaxApyVault _vault, IStrategyWrapper _strategy, MockERC20 _token) {
        strategy = _strategy;
        token = _token;
        vault = _vault;
    }

    ////////////////////////////////////////////////////////////////
    ///                      ENTRY POINTS                        ///
    ////////////////////////////////////////////////////////////////
    function gain(uint256 amount) public override countCall("gain") {
        amount = bound(amount, 0, 1_000_000 ether);
        expectedEstimatedTotalAssets = actualEstimatedTotalAssets;
        deal(address(token), address(strategy), amount);
    }

    function triggerLoss(uint256 amount, bool useLiquidateExact) public override countCall("triggerLoss") {
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
            uint256 _expectedEstimatedTotalAssets = strategy.estimatedTotalAssets();
            uint256 loss = strategy.liquidateExact(amount);
            expectedEstimatedTotalAssets = _sub0(_expectedEstimatedTotalAssets, amount + loss);
            assertGe(strategyPreview, amount + loss);
        }
        actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
    }

    function harvest() public override countCall("harvest") {
        uint256 creditAvailable = vault.creditAvailable(address(strategy));
        uint256 debtOutstanding = vault.debtOutstanding(address(strategy));
        int256 unharvestedAmount = strategy.unharvestedAmount();
        if (unharvestedAmount < 0) {
            expectedEstimatedTotalAssets = actualEstimatedTotalAssets + creditAvailable;
            strategy.harvest(0, 0, address(0), block.timestamp);
        }

        if (unharvestedAmount >= 0) {
            expectedEstimatedTotalAssets = actualEstimatedTotalAssets
                + _sub0(uint256(unharvestedAmount), vault.debtOutstanding(address(strategy))) + creditAvailable;
            strategy.harvest(0, 0, address(0), block.timestamp);
        }
        actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
    }

    ////////////////////////////////////////////////////////////////
    ///                      INVARIANTS                          ///
    ////////////////////////////////////////////////////////////////
    function INVARIANT_A_ESTIMATED_TOTAL_ASSETS() public view override {
        assertEq(expectedEstimatedTotalAssets, actualEstimatedTotalAssets);
    }
}
