// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseHandler, console2 } from "./BaseHandler.t.sol";

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
        bytes4[] memory _entryPoints = new bytes4[](2);
        _entryPoints[0] = this.gain.selector;
        _entryPoints[1] = this.harvest.selector;
       // _entryPoints[2] = this.triggerLoss.selector;
        return _entryPoints;
    }

    function callSummary() public view override {
        console2.log("");
        console2.log("");
        console2.log("Call summary:");
        console2.log("-------------------");
        console2.log("gain", calls["gain"]);
        console2.log("trigerLoss", calls["trigerLoss"]);
        console2.log("harvest", calls["harvest"]);
        console2.log("-------------------");
    }

    ////////////////////////////////////////////////////////////////
    ///                      INVARIANTS                          ///
    ////////////////////////////////////////////////////////////////
    function INVARIANT_A_ESTIMATED_TOTAL_ASSETS() public view virtual;
}
