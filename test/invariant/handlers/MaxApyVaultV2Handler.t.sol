// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { BaseHandler, console } from "./base/BaseHadler.t.sol";
import { MaxApyVaultV2 } from "src/MaxApyVaultV2.sol";
import { MockERC20 } from "../../mock/MockERC20.sol";

contract MaxApyVaultV2Handler is BaseHandler {
    MaxApyVaultV2 vault;
    MockERC20 token;

    ////////////////////////////////////////////////////////////////
    ///                      GHOST VARIABLES                     ///
    ////////////////////////////////////////////////////////////////
    uint256 public expectedTotalSupply;
    uint256 public actualTotalSupply;

    uint256 public expectedTotalAssets;
    uint256 public actualTotalAssets;

    uint256 public expectedTotalIdle;
    uint256 public actualTotalIdle;

    uint256 public expectedTotalDebt;
    uint256 public actualTotalDebt;

    uint256 public expectedTotalDeposits;
    uint256 public actualTotalDeposits;

    uint256 public expectedSharePrice;
    uint256 public actualSharePrice;

    uint256 public expectedShares;
    uint256 public actualShares;

    uint256 public expectedAssets;
    uint256 public actualAssets;

    uint256 public expectedBalance;
    uint256 public actualBalance;

    uint256 public sharePriceDelta;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////
    constructor(MaxApyVaultV2 _vault, MockERC20 _token) {
        vault = _vault;
        token = _token;
    }

    function deposit(uint256 amount) public createActor countCall("deposit") {
        amount = bound(amount, 0, vault.maxDeposit(currentActor));
        if (amount == 0) return;
        if (currentActor == address(vault)) return;

        deal(address(token), currentActor, amount);

        uint256 previousSharePrice = vault.sharePrice();
        expectedBalance = actualBalance + amount;
        expectedShares = vault.previewDeposit(amount);
        expectedTotalSupply = actualTotalSupply + expectedShares;
        expectedTotalAssets = actualTotalAssets + amount;
        expectedTotalDeposits = actualTotalDeposits + amount;
        expectedTotalIdle = actualTotalIdle + amount;
        expectedTotalDebt = 0;
        expectedSharePrice = (10 ** vault.decimals()) * (expectedTotalAssets + 1) / (expectedTotalSupply + 10 ** 6);

        vm.startPrank(currentActor);
        token.approve(address(vault), type(uint256).max);
        actualShares = vault.deposit(amount, currentActor);
        vm.stopPrank();

        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();
        sharePriceDelta = (
            actualSharePrice > previousSharePrice
                ? actualSharePrice - previousSharePrice
                : previousSharePrice - actualSharePrice
        ) * 10_000 / previousSharePrice;
    }

    function mint(uint256 shares) public createActor countCall("mint") {
        shares = bound(shares, 0, vault.maxMint(currentActor));
        if (shares == 0) return;
        if (currentActor == address(vault)) return;

        expectedAssets = vault.previewMint(shares);
        deal(address(token), currentActor, expectedAssets * 2);

        uint256 previousSharePrice = vault.sharePrice();
        expectedBalance = actualBalance + expectedAssets;
        expectedTotalSupply = actualTotalSupply + shares;
        expectedTotalAssets = actualTotalAssets + expectedAssets;
        expectedTotalDeposits = actualTotalDeposits + expectedAssets;
        expectedTotalIdle = actualTotalIdle + expectedAssets;
        expectedTotalDebt = 0;
        expectedSharePrice = (10 ** vault.decimals()) * (expectedTotalAssets + 1) / (expectedTotalSupply + 10 ** 6);

        vm.startPrank(currentActor);
        token.approve(address(vault), type(uint256).max);
        actualAssets = vault.mint(shares, currentActor);
        vm.stopPrank();

        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();
        sharePriceDelta = (
            actualSharePrice > previousSharePrice
                ? actualSharePrice - previousSharePrice
                : previousSharePrice - actualSharePrice
        ) * 10_000 / previousSharePrice;
    }

    function redeem(uint256 actorSeed, uint256 shares) public useActor(actorSeed) countCall("redeem") {
        shares = bound(shares, 0, vault.maxRedeem(currentActor));
        if (shares == 0) return;
        if (currentActor == address(vault)) return;

        uint256 previousSharePrice = vault.sharePrice();
        expectedAssets = vault.previewRedeem(shares);
        expectedBalance = actualBalance - expectedAssets;
        expectedTotalSupply = actualTotalSupply - shares;
        expectedTotalAssets = actualTotalAssets - expectedAssets;
        expectedTotalDeposits = actualTotalDeposits - expectedAssets;
        expectedTotalIdle = actualTotalIdle - expectedAssets;
        expectedTotalDebt = 0;
        expectedSharePrice = (10 ** vault.decimals()) * (expectedTotalAssets + 1) / (expectedTotalSupply + 10 ** 6);

        vm.startPrank(currentActor);
        actualAssets = vault.redeem(shares, currentActor, currentActor);
        vm.stopPrank();

        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();
        sharePriceDelta = (
            actualSharePrice > previousSharePrice
                ? actualSharePrice - previousSharePrice
                : previousSharePrice - actualSharePrice
        ) * 10_000 / previousSharePrice;
    }

    function withdraw(uint256 actorSeed, uint256 assets) public useActor(actorSeed) countCall("withdraw") {
        assets = bound(assets, 0, vault.maxWithdraw(currentActor));
        if (assets == 0) return;
        if (currentActor == address(vault)) return;

        uint256 previousSharePrice = vault.sharePrice();
        expectedShares = vault.previewWithdraw(assets);
        console.log("actual balance : ", actualBalance);
        console.log("withdraw assets : ", assets);
        expectedBalance = actualBalance - assets;
        console.log ("actual totalSupply : ", actualTotalSupply);
        console.log ("expectedShares : ", expectedShares);
        if(actualTotalSupply < expectedShares) return; // trying to withdraw too few assets
        expectedTotalSupply = actualTotalSupply - expectedShares;
        expectedTotalAssets = actualTotalAssets - assets;
        expectedTotalDeposits = actualTotalDeposits - assets;
        expectedTotalIdle = actualTotalIdle - assets;
        expectedTotalDebt = 0;
        expectedSharePrice = (10 ** vault.decimals()) * (expectedTotalAssets + 1) / (expectedTotalSupply + 10 ** 6);

        vm.startPrank(currentActor);
        actualShares = vault.withdraw(assets, currentActor, currentActor);
        vm.stopPrank();

        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();
        sharePriceDelta = (
            actualSharePrice > previousSharePrice
                ? actualSharePrice - previousSharePrice
                : previousSharePrice - actualSharePrice
        ) * 10_000 / previousSharePrice;
    }

    ////////////////////////////////////////////////////////////////
    ///                      HELPERS                             ///
    ////////////////////////////////////////////////////////////////

    function getEntryPoints() public pure override returns (bytes4[] memory) {
        bytes4[] memory _entryPoints = new bytes4[](4);
        _entryPoints[0] = this.deposit.selector;
        _entryPoints[1] = this.redeem.selector;
        _entryPoints[2] = this.mint.selector;
        _entryPoints[3] = this.withdraw.selector;
        return _entryPoints;
    }

    function callSummary() public view override {
        console.log("");
        console.log("");
        console.log("Call summary:");
        console.log("-------------------");
        console.log("deposit", calls["deposit"]);
        console.log("mint", calls["mint"]);
        console.log("redeem", calls["redeem"]);
        console.log("withdraw", calls["withdraw"]);
        console.log("-------------------");
    }
}
