// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseSommelierStrategy, SafeTransferLib } from "src/strategies/base/BaseSommelierStrategy.sol";

/// @title SommelierTurboGHOStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/Strategy.sol
/// @notice `SommelierTurboGHOStrategy` supplies an underlying token into a generic Sommelier Vault,
/// earning the Sommelier Vault's yield
contract SommelierTurboGHOStrategy is BaseSommelierStrategy { }
