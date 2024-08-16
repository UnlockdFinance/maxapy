// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { MockERC4626 } from "./MockERC4626.sol";

contract MockCellar is MockERC4626 {
    bool public isPaused;
    bool public isShutdown;

    constructor(
        address underlying_,
        string memory name_,
        string memory symbol_,
        bool useVirtualShares_,
        uint8 decimalsOffset_
    )
        MockERC4626(underlying_, name_, symbol_, useVirtualShares_, decimalsOffset_)
    { }
}
