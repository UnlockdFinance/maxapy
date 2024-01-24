// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {IStrategy} from "./IStrategy.sol";

interface IConvexdETHFrxETHStrategy is IStrategy {
    function setRouter(address _router) external;

    /// roles
    function ADMIN_ROLE() external returns (uint256);

    function EMERGENCY_ADMIN_ROLE() external returns (uint256);

    function VAULT_ROLE() external returns (uint256);

    function KEEPER_ROLE() external returns (uint256);

    function owner() external returns (address);

    /// view

    function maxSingleTrade() external returns (uint256);

    function minSingleTrade() external returns (uint256);

    function minSwapCrv() external returns (uint256);

    function minSwapCvx() external returns (uint256);

    function setMinSwapCrv(uint256 _minSwapCrv) external;

    function setMinSwapCvx(uint256 _minSwapCvx) external;

    function setMaxSingleTrade(uint256 _maxSingleTrade) external;

    function setMinSingleTrade(uint256 _minSingleTrade) external;

    function convexBooster() external view returns (address);

    function pid() external view returns (uint256);

    function convexRewardPool() external view returns (address);

    function convexLpToken() external view returns (address);

    function rewardToken() external view returns (address);

    function curvePool() external view returns (address);

    function crvWethPool() external view returns (address);

    function cvxWethPool() external view returns (address);

    function router() external view returns (address);

    function unwindRewards() external;
}
