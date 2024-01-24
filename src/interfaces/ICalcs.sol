// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

interface ICalcs {
    function previewDeposit(uint256 shares, uint256 amount) external view returns (uint256, uint256);
    function previewWithdraw(uint256 shares, uint256 amount) external view returns (uint256, uint256);
    function shareValue(uint256 shares) external view returns (uint256);
    function sharesForAmount(uint256 amount) external view returns (uint256);
}
