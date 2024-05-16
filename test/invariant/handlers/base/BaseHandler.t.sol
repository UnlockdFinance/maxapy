// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { console } from "forge-std/console.sol";
import { AddressSet, LibAddressSet } from "../../../helpers/AddressSet.sol";

abstract contract BaseHandler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    ////////////////////////////////////////////////////////////////
    ///                      ACTORS CONFIG                       ///
    ////////////////////////////////////////////////////////////////
    mapping(bytes32 => uint256) public calls;

    AddressSet internal _actors;
    address internal currentActor;

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(msg.sender);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    ////////////////////////////////////////////////////////////////
    ///                      HELPERS                             ///
    ////////////////////////////////////////////////////////////////
    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
    }

    function _sub0(uint256 a, uint256 b) internal pure virtual returns (uint256) {
        unchecked {
            return a - b > a ? 0 : a - b;
        }
    }

    function reduceActors(
        uint256 acc,
        function(uint256,address) external returns (uint256) func
    )
        public
        returns (uint256)
    {
        return _actors.reduce(acc, func);
    }

    function actors() public view returns (address[] memory) {
        return _actors.addrs;
    }

    function callSummary() public view virtual;

    function getEntryPoints() public view virtual returns (bytes4[] memory);
}
