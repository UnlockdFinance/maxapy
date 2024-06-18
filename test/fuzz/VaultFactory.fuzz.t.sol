// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { VaultFactory } from "src/VaultFactory.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

contract VaultFactoryFuzzTest is Test {
    event CreateVault(address indexed asset, address vaultAddress);

    MockERC20 asset;
    address treasury = makeAddr("treasury");
    address deployer = makeAddr("deployer");
    VaultFactory public factory;

    function setUp() public {
        factory = new VaultFactory(treasury);
        factory.grantRoles(deployer, factory.DEPLOYER_ROLE());
        asset = new MockERC20("Wrapped Ethereum", "WETH", 18);
    }

    function testFuzzDeployDeterministicVault(bytes32 salt) public {
        address computedAddress = factory.computeAddress(salt);
        vm.prank(deployer);
        address deployed = factory.deploy(address(asset), salt);
        IMaxApyVault deployedVault = IMaxApyVault(deployed);
        string memory expectedName = "MaxApy-WETH Vault";
        string memory expectedSymbol = "maxWETH";
        assertEq(keccak256(abi.encodePacked(expectedName)), keccak256(abi.encodePacked(deployedVault.name())));
        assertEq(keccak256(abi.encodePacked(expectedSymbol)), keccak256(abi.encodePacked(deployedVault.symbol())));
        assertEq(deployed, computedAddress);
    }
}
