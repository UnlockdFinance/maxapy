// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { console } from "forge-std/console.sol";
import { AddressSet, LibAddressSet } from "../../helpers/AddressSet.sol";
import { MaxApyVaultV2 } from "src/MaxApyVaultV2.sol";
import { MockERC20 } from "../../mock/MockERC20.sol";

contract MaxApyVaultV2Handler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    MaxApyVaultV2 vault;
    MockERC20 token;

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

        token.mint(currentActor, amount);

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

        expectedAssets = vault.convertToAssets(shares);
        token.mint(currentActor, expectedAssets);

        uint256 previousSharePrice = vault.sharePrice();
        expectedBalance = actualBalance + expectedAssets;
        expectedTotalSupply = actualTotalSupply + shares;
        expectedTotalAssets = actualTotalAssets + expectedAssets;
        expectedTotalDeposits = actualTotalDeposits + expectedAssets;
        expectedTotalIdle = actualTotalIdle + expectedAssets;
        expectedTotalDebt = 0;
        expectedSharePrice = (10 ** vault.decimals()) * (expectedTotalAssets + 1) / (expectedTotalSupply + 10 ** 6);

        actualAssets = vault.mint(shares, currentActor);

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
        shares = bound(shares, 0, vault.balanceOf(currentActor));
        if (shares == 0) return;

        uint256 previousSharePrice = vault.sharePrice();
        expectedAssets = vault.previewRedeem(shares);
        expectedBalance = actualBalance - expectedAssets;
        expectedTotalSupply = actualTotalSupply - shares;
        expectedTotalAssets = actualTotalAssets - expectedAssets;
        expectedTotalDeposits = actualTotalDeposits - expectedAssets;
        expectedTotalIdle = actualTotalIdle - expectedAssets;
        expectedTotalDebt = 0;
        expectedSharePrice = (10 ** vault.decimals()) * (expectedTotalAssets + 1) / (expectedTotalSupply + 10 ** 6);

        vm.prank(currentActor);
        actualAssets = vault.redeem(shares, currentActor, currentActor);

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

    function withdraw(uint256 actorSeed, uint256 shares) public useActor(actorSeed) countCall("withdraw") {
        shares = bound(shares, 0, vault.balanceOf(currentActor));
        if (shares == 0) return;

        token.mint(currentActor, shares);

        expectedAssets = vault.previewRedeem(shares);
        expectedBalance = actualBalance - expectedAssets;
        expectedTotalSupply = actualTotalSupply - shares;
        expectedTotalAssets = actualTotalAssets - expectedAssets;
        expectedTotalDeposits = actualTotalDeposits - expectedAssets;
        expectedTotalIdle = actualTotalIdle - expectedAssets;
        expectedTotalDebt = 0;
        expectedSharePrice = (10 ** vault.decimals()) * (expectedTotalAssets + 1) / (expectedTotalSupply + 10 ** 6);

        actualAssets = vault.withdraw(shares, currentActor, currentActor);

        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();
    }

    ////////////////////////////////////////////////////////////////
    ///                      HELPERS                             ///
    ////////////////////////////////////////////////////////////////
    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
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

    function actors() external view returns (address[] memory) {
        return _actors.addrs;
    }

    function callSummary() external view {
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
