// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseFuzzer, console, LibAddressSet, AddressSet } from "./base/BaseFuzzer.t.sol";
import { IMaxApyVaultV2 } from "src/interfaces/IMaxApyVaultV2.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";
import { LibPRNG } from "solady/utils/LibPRNG.sol";

contract MaxApyVaultV2Fuzzer is BaseFuzzer {
    using LibAddressSet for AddressSet;

    AddressSet strats;
    IMaxApyVaultV2 vault;
    address token;

    constructor(address[] memory _strats, IMaxApyVaultV2 _vault, address _token) {
        for (uint256 i = 0; i < _strats.length; i++) {
            strats.add(_strats[i]);
        }
        vault = _vault;
        token = _token;
    }

    function harvest(uint256 strategySeed) public {
        address strat = strats.rand(strategySeed);
        IStrategyWrapper(strat).harvest(0, 0, 0, address(0));
        skip(100);
    }

    function gain(uint256 assets) public { }
}
