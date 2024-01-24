// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

contract BaseStrategyEvents {
    event StrategyEmergencyExitUpdated(address indexed strategy, uint256 emergencyExitStatus);
    event StrategistUpdated(address indexed strategy, address newStrategist);
}
