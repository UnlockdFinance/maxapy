// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseFuzzer, console2, LibAddressSet, AddressSet } from "./base/BaseFuzzer.t.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";
import { LibPRNG } from "solady/utils/LibPRNG.sol";

contract StrategyFuzzer is BaseFuzzer {
    using LibAddressSet for AddressSet;
    using LibPRNG for LibPRNG.PRNG;

    AddressSet strats;
    IMaxApyVault vault;
    address token;

    constructor(address[] memory _strats, IMaxApyVault _vault, address _token) {
        for (uint256 i = 0; i < _strats.length; i++) {
            strats.add(_strats[i]);
        }
        vault = _vault;
        token = _token;
    }

    function harvest(LibPRNG.PRNG memory strategySeedRNG) public {
        if (strats.count() == 0) return;
        address strat = strats.rand(strategySeedRNG.next());
        try IStrategyWrapper(strat).harvest(0, 0, address(0), block.timestamp) {
            skip(100);
        } catch (bytes memory e) {
            e;
        }
    }

    function exitStrategy(LibPRNG.PRNG memory strategySeedRNG) public {
        if (strats.count() == 0) return;
        address strat = strats.rand(strategySeedRNG.next());
        vault.exitStrategy(strat);
        strats.remove(strat);
    }

    function gain(LibPRNG.PRNG memory strategySeedRNG, uint256 amount) public {
        if (strats.count() == 0) return;
        address strat = strats.rand(strategySeedRNG.next());
        deal(token, strat, amount);
    }

    function loss(LibPRNG.PRNG memory strategySeedRNG, uint256 amount) public { }

    function rand(uint256 functionSeed, uint256 paramSeed) public {
        LibPRNG.PRNG memory rngParams;
        rngParams.seed(paramSeed);
    }
}
