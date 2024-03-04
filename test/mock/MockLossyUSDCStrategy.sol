// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {IMaxApyVaultV2} from "src/interfaces/IMaxApyVaultV2.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract MockLossyUSDCStrategy {
    address public immutable vault;
    address public immutable underlyingAsset;
    address public immutable strategist;
    uint256 public estimatedTotalAssets;

    uint256 constant _1_USDC = 1e6;
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
        if (amount <= _1_USDC) return (0);
        IERC20(underlyingAsset).transfer(msg.sender, amount - _1_USDC);
        return _1_USDC;
    }

    function requestWithdraw(uint256 amount) external returns (uint256) {
        IERC20(underlyingAsset).transfer(msg.sender, amount);
        return _1_USDC;
    }

    function previewWithdrawRequest(uint256 amount) external pure returns (uint256) {
        return amount + _1_USDC;
    }

    function previewWithdraw(uint256 amount) external pure returns (uint256) {
        return amount - _1_USDC;
    }

    function maxRequest() external view returns (uint256) {
        return estimatedTotalAssets == 0 ? 0 : estimatedTotalAssets - _1_USDC;
    }

    function maxWithdraw() external view returns (uint256) {
        return estimatedTotalAssets;
    }

    function mockReport(uint128 gain, uint128 loss, uint128 debtPayment, address treasury) external {
        IMaxApyVaultV2(vault).report(gain, gain, loss, debtPayment, treasury);
    }

    function delegatedAssets() external pure returns (uint256) {
        return 0;
    }
}
