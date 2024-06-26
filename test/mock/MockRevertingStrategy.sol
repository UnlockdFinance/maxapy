// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

contract MockRevertingStrategy {
    error HarvestFailed();

    address public immutable vault;
    address public immutable underlyingAsset;

    uint256 public emergencyExit;

    address public strategist;

    constructor(address _vault, address _underlyingAsset) {
        vault = _vault;
        underlyingAsset = _underlyingAsset;
        strategist = msg.sender;
    }

    function setEmergencyExit(uint256 _emergencyExit) external {
        emergencyExit = _emergencyExit;
    }

    function setStrategist(address _newStrategist) external {
        strategist = _newStrategist;
    }

    function harvest(
        uint256 minExpectedBalance,
        uint256 minOutputAfterInvestment,
        address harvester,
        uint256 deadline
    )
        external
    {
        revert HarvestFailed();
    }

    function setAutopilot(bool _autoPilot) external {
        IMaxApyVault(vault).setAutoPilot(_autoPilot);
    }

    function estimatedTotalAssets() external view returns (uint256) {
        return 0;
    }
}
