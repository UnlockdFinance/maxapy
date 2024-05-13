// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { IStrategy } from "./IStrategy.sol";

interface IYearnStrategy is IStrategy {
    /// roles
    function ADMIN_ROLE() external returns (uint256);

    function EMERGENCY_ADMIN_ROLE() external returns (uint256);

    function VAULT_ROLE() external returns (uint256);

    function KEEPER_ROLE() external returns (uint256);

    /// view
    function yVault() external returns (address);

    function maxSingleTrade() external returns (uint256);

    function minSingleTrade() external returns (uint256);

    function setMaxSingleTrade(uint256 _maxSingleTrade) external;

    function setMinSingleTrade(uint256 _minSingleTrade) external;
}
