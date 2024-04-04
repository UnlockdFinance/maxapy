// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {IMaxApyVaultV2} from "src/interfaces/IMaxApyVaultV2.sol";

interface IMaxApyRouter {
    function deposit(IMaxApyVaultV2 vault, uint256 amount, address recipient, uint256 minSharesOut)
        external
        payable
        returns (uint256);

    function depositNative(IMaxApyVaultV2 vault, address recipient, uint256 minSharesOut)
        external
        payable
        returns (uint256);

    function redeem(IMaxApyVaultV2 vault, uint256 shares, address recipient, uint256 minAmountOut)
        external
        returns (uint256);

    function redeemNative(IMaxApyVaultV2 vault, uint256 shares, address recipient, uint256 minAmountOut)
        external
        returns (uint256);
}
