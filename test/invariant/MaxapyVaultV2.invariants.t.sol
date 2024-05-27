// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { MaxApyVaultV2Handler, MockERC20, MaxApyVaultV2 } from "./handlers/MaxApyVaultV2Handler.t.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";

contract MaxApyVaultV2AccountingInvariants is StdInvariant, Test {
    MaxApyVaultV2Handler mvh;

    function setUp() public {
        MockERC20 _token = new MockERC20("MockERC20", "MERC", 6);
        MaxApyVaultV2 _vault = new MaxApyVaultV2(address(_token), "MaxApyVault", "max", address(1));
        mvh = new MaxApyVaultV2Handler(_vault, _token);
        targetContract(address(mvh));
        bytes4[] memory selectors = mvh.getEntryPoints();
        targetSelector(FuzzSelector({ addr: address(mvh), selectors: selectors }));
        vm.label(address(_token), "WETH");
        vm.label(address(_vault), "VAULT");
        vm.label(address(mvh), "MVH");
    }

    function invariantMaxApyVaultV2__SharePreviews() public {
        assertEq(mvh.actualShares(), mvh.expectedShares());
    }

    function invariantMaxApyVaultV2__AssetsPreviews() public {
        assertEq(mvh.actualAssets(), mvh.expectedAssets());
    }

    function invariantMaxApyVaultV2__InternalAccounting() public {
        assertEq(mvh.actualTotalSupply(), mvh.expectedTotalSupply());
        assertEq(mvh.actualTotalIdle(), mvh.expectedTotalIdle());
        assertEq(mvh.actualTotalDebt(), mvh.expectedTotalDebt());
        assertEq(mvh.actualTotalAssets(), mvh.expectedTotalAssets());
        assertEq(mvh.actualTotalDeposits(), mvh.expectedTotalDeposits());
        assertEq(mvh.actualBalance(), mvh.expectedBalance());
    }

    function invariantMaxApyVaultV2__SharePrice() public {
        assertEq(mvh.actualSharePrice(), mvh.expectedSharePrice());
        // NOTE: share price can dramatically change in some edge cases
        // assertLe(mvh.sharePriceDelta(), 100,  "invariant: share price delta"); // 1%
    }

    function invariantMaxApyVaultV2__CallSummary() public view {
        mvh.callSummary();
    }
}
