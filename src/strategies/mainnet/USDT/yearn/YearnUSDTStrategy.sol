// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseYearnV2Strategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseYearnV2Strategy.sol";

/// @title YearnUSDTStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnUSDTStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnUSDTStrategy is BaseYearnV2Strategy { }
