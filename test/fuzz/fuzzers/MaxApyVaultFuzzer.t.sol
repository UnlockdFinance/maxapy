// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseFuzzer, console } from "./base/BaseFuzzer.t.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { LibPRNG } from "solady/utils/LibPRNG.sol";

contract MaxApyVaultFuzzer is BaseFuzzer {
    using SafeTransferLib for address;
    using LibPRNG for LibPRNG.PRNG;

    LibPRNG.PRNG rng;
    IMaxApyVault vault;
    address token;

    constructor(IMaxApyVault _vault, address _token) {
        vault = _vault;
        token = _token;
    }

    function deposit(uint256 assets) public createActor {
        assets = bound(assets, 0, vault.maxDeposit(currentActor));
        deal(token, currentActor, assets);
        uint256 expectedShares = vault.previewDeposit(assets);
        vm.startPrank(currentActor);
        token.safeApprove(address(vault), assets);
        if (assets == 0 || expectedShares == 0) vm.expectRevert();
        uint256 actualShares = vault.deposit(assets, currentActor);
        assertEq(actualShares, expectedShares);
        vm.stopPrank();
    }

    function mint(uint256 shares) public createActor {
        shares = bound(shares, 0, vault.maxMint(currentActor));
        uint256 expectedAssets = vault.previewMint(shares);
        deal(token, currentActor, expectedAssets * 2);
        vm.startPrank(currentActor);
        token.safeApprove(address(vault), type(uint256).max);
        if (shares == 0 || expectedAssets == 0 || expectedAssets > token.balanceOf(currentActor)) vm.expectRevert();
        uint256 actualAssets = vault.mint(shares, currentActor);
        assertEq(actualAssets, expectedAssets);
        vm.stopPrank();
    }

    function redeem(uint256 actorSeed, uint256 shares) public useActor(actorSeed) {
        shares = bound(shares, 0, vault.maxRedeem(currentActor));
        uint256 expectedAssets = vault.previewRedeem(shares);
        vm.startPrank(currentActor);
        if (shares == 0 || expectedAssets == 0) vm.expectRevert();
        uint256 actualAssets = vault.redeem(shares, currentActor, currentActor);
        assertGe(actualAssets, expectedAssets);
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint256 assets) public useActor(actorSeed) {
        assets = bound(assets, 0, vault.maxWithdraw(currentActor));
        uint256 expectedShares = vault.previewWithdraw(assets);
        vm.startPrank(currentActor);
        if (assets == 0 || expectedShares == 0) vm.expectRevert();
        uint256 actualShares = vault.withdraw(assets, currentActor, currentActor);
        assertLe(actualShares, expectedShares);
        vm.stopPrank();
    }

    function rand(uint256 functionSeed) public { }
}
