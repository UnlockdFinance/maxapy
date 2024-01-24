// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {IERC777} from "./MockERC777.sol";

import {IMaxApyVaultV2} from "../../src/interfaces/IMaxApyVaultV2.sol";

contract ReentrantERC777AttackerDeposit {
    IMaxApyVaultV2 public vault;

    function setVault(IMaxApyVaultV2 _vault) public {
        vault = _vault;
    }

    function attack(uint256 amount) public {
        vault.deposit(amount, address(this));
    }

    function tokensReceived(address, address from, address, uint256 amount, bytes calldata, bytes calldata) external {
        // reenter here
        if (from != address(0)) {
            vault.deposit(amount, address(this));
        }
    }
}
