// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseHandler, console } from "./base/BaseHandler.t.sol";
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

    function gain(uint256 amount) public countCall("gain") {
        amount = bound(amount, 0, 1_000_000 ether);
        deal(address(token), address(strategy), amount);
    }

    function triggerLoss(uint256 amount, bool useLiquidateExact) public countCall("triggerLoss") {
        if(!useLiquidateExact) {
            amount = bound(amount, 0, strategy.maxLiquidate());
            if (amount == 0) return;
            expectedEstimatedTotalAssets = _sub0(strategy.estimatedTotalAssets(), amount);
            strategy.liquidate(amount);
        }
        else {
            amount = bound(amount, 0, strategy.maxLiquidateExact());
            if (amount == 0) return;
            uint256 loss = strategy.liquidateExact(amount);
            expectedEstimatedTotalAssets = _sub0(strategy.estimatedTotalAssets(), amount);
        }
        actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
    }

    function harvest() public countCall("harvest") {
        int256 unharvestedAmount = strategy.unharvestedAmount();
        if(unharvestedAmount < 0) {
            expectedEstimatedTotalAssets = actualEstimatedTotalAssets;
            strategy.harvest(0,0,0, address(0));
            actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
        }

        if(unharvestedAmount > 0) {
            expectedEstimatedTotalAssets = strategy.estimatedTotalAssets() + uint256(strategy.unharvestedAmount());
            strategy.harvest(0,0,0, address(0));
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
