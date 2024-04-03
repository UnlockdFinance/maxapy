// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Permit, ERC20} from "openzeppelin/token/ERC20/extensions/ERC20Permit.sol";

contract MockToken is ERC20Permit {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}