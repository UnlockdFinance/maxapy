// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {IERC777} from "./MockERC777.sol";

import {IMaxApyVaultV2} from "src/interfaces/IMaxApyVaultV2.sol";

contract ReentrantERC777AttackerWithdraw {
    IMaxApyVaultV2 public vault;

    uint256 counter;

    function setVault(IMaxApyVaultV2 _vault) public {
        vault = _vault;
    }

    function attack(uint256 amount) public {
        vault.redeem(amount, address(this), address(this));
    }

    function tokensReceived(address, address from, address, uint256 amount, bytes calldata, bytes calldata) external {
        if (from != address(0)) {
            vault.redeem(amount, address(this), address(this));
        }

        unchecked {
            ++counter;
        }
    }
}
