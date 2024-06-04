// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseHandler, console } from "./BaseHandler.t.sol";

abstract contract BaseStrategyHandler is BaseHandler {
    ////////////////////////////////////////////////////////////////
    ///                      GHOST VARIABLES                     ///
    ////////////////////////////////////////////////////////////////
    uint256 public expectedEstimatedTotalAssets;
    uint256 public actualEstimatedTotalAssets;

    ////////////////////////////////////////////////////////////////
    ///                      ENTRY POINTS                        ///
    ////////////////////////////////////////////////////////////////
    function harvest() public virtual;

    function gain(uint256 amount) public virtual;

    function triggerLoss(uint256 amount, bool useLiquidateExact) public virtual;

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

    ////////////////////////////////////////////////////////////////
    ///                      INVARIANTS                          ///
    ////////////////////////////////////////////////////////////////
    function INVARIANT_A_ESTIMATED_TOTAL_ASSETS() public view virtual;
}
