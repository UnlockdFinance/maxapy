// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {IMaxApyVaultV2} from "../../src/interfaces/IMaxApyVaultV2.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract MockLossyUSDCStrategy {
    address public immutable vault;
    address public immutable underlyingAsset;
    address public immutable strategist;
    uint256 public estimatedTotalAssets;

    uint256 public emergencyExit;

    constructor(address _vault, address _underlyingAsset, address _strategist) {
        vault = _vault;
        underlyingAsset = _underlyingAsset;
        IERC20(_underlyingAsset).approve(_vault, type(uint256).max);
        strategist = _strategist;
    }

    function setEmergencyExit(uint256 _emergencyExit) external {
        emergencyExit = _emergencyExit;
    }

    function setEstimatedTotalAssets(uint256 _estimatedTotalAssets) external {
        estimatedTotalAssets = _estimatedTotalAssets;
    }

    function withdraw(uint256 amount) external returns (uint256) {
        IERC20(underlyingAsset).transfer(msg.sender, amount - 10 ** 6);
        return 10 ** 6;
    }

    function previewWithdrawRequest(uint256 amount) external pure returns (uint256) {
        return amount + 10 ** 6;
    }

    function previewWithdraw(uint256 amount) external pure returns (uint256) {
        return amount - 10 ** 6;
    }

    function mockReport(uint128 gain, uint128 loss, uint128 debtPayment) external {
        IMaxApyVaultV2(vault).report(gain, gain, loss, debtPayment);
    }

    function delegatedAssets() external pure returns (uint256) {
        return 0;
    }
}
