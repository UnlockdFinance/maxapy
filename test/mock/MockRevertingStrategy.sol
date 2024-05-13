// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { IMaxApyVaultV2 } from "src/interfaces/IMaxApyVaultV2.sol";

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
        uint256 harvestedProfitBPS,
        address harvester
    )
        external
    {
        revert HarvestFailed();
    }

    function setAutopilot(bool _autoPilot) external {
        IMaxApyVaultV2(vault).setAutoPilot(_autoPilot);
    }

    function estimatedTotalAssets() external view returns (uint256) {
        return 0;
    }
}
