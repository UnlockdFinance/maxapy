// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { MaxApyVaultHandler, MockERC20, MaxApyVault } from "./handlers/MaxApyVaultHandler.t.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";

contract MaxApyVaultAccountingInvariants is StdInvariant, Test {
    MaxApyVaultHandler mvh;

    function setUp() public {
        MockERC20 _token = new MockERC20("MockERC20", "MERC", 6);
        MaxApyVault _vault = new MaxApyVault(address(_token), "MaxApyVault", "max", address(1));
        mvh = new MaxApyVaultHandler(_vault, _token);
        targetContract(address(mvh));
        bytes4[] memory selectors = mvh.getEntryPoints();
        targetSelector(FuzzSelector({ addr: address(mvh), selectors: selectors }));
        vm.label(address(_token), "WETH");
        vm.label(address(_vault), "VAULT");
        vm.label(address(mvh), "MVH");
    }

    function invariantMaxApyVault__SharePreviews() public {
        assertEq(mvh.actualShares(), mvh.expectedShares());
    }

    function invariantMaxApyVault__AssetsPreviews() public {
        assertEq(mvh.actualAssets(), mvh.expectedAssets());
    }

    function invariantMaxApyVault__InternalAccounting() public {
        assertEq(mvh.actualTotalSupply(), mvh.expectedTotalSupply());
        assertEq(mvh.actualTotalIdle(), mvh.expectedTotalIdle());
        assertEq(mvh.actualTotalDebt(), mvh.expectedTotalDebt());
        assertEq(mvh.actualTotalAssets(), mvh.expectedTotalAssets());
        assertEq(mvh.actualTotalDeposits(), mvh.expectedTotalDeposits());
        assertEq(mvh.actualBalance(), mvh.expectedBalance());
    }

    function invariantMaxApyVault__SharePrice() public {
        assertEq(mvh.actualSharePrice(), mvh.expectedSharePrice());
        // NOTE: share price can dramatically change in some edge cases
        // assertLe(mvh.sharePriceDelta(), 100,  "invariant: share price delta"); // 1%
    }

    function invariantMaxApyVault__CallSummary() public view {
        mvh.callSummary();
    }
}
