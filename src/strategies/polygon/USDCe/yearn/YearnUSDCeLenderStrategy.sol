// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseYearnV3Strategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseYearnV3Strategy.sol";

/// @title YearnUSDCeLenderStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnUSDCeLenderStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnUSDCeLenderStrategy is BaseYearnV3Strategy { }
