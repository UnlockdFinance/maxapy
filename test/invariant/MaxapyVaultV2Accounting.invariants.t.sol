// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { MaxApyVaultV2Handler, MockERC20, MaxApyVaultV2 } from "./handlers/MaxApyVaultV2Handler.t.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";

contract MaxaApyVaultV2AccountinhInvariants is StdInvariant, Test {
    MaxApyVaultV2Handler mvh;

    function setUp() public {
        MockERC20 _token = new MockERC20("MockERC20", "MERC", 6);
        MaxApyVaultV2 _vault = new MaxApyVaultV2(address(_token), "MaxApyVault", "max", address(1));
        mvh = new MaxApyVaultV2Handler(_vault, _token);
        targetContract(address(mvh));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = MaxApyVaultV2Handler.deposit.selector;
        selectors[1] = MaxApyVaultV2Handler.redeem.selector;
        targetSelector(FuzzSelector({ addr: address(mvh), selectors: selectors }));
    }

    function invariantMaxApyVaultV2__Accounting() public {
        assertEq(mvh.actualAssets(), mvh.expectedAssets(), "invariant: redeem assets");
        assertEq(mvh.actualShares(), mvh.expectedShares(), "invariant: deposit shares");
        assertEq(mvh.actualTotalSupply(), mvh.expectedTotalSupply(), "invariant: shares supply");
        assertEq(mvh.actualTotalIdle(), mvh.expectedTotalIdle(), "invariant: total idle");
        assertEq(mvh.actualTotalDebt(), mvh.expectedTotalDebt(), "invariant: total debt");
        assertEq(mvh.actualTotalAssets(), mvh.expectedTotalAssets(), "invariant: total assets");
        assertEq(mvh.actualTotalDeposits(), mvh.expectedTotalDeposits(), "invariant: total deposits");
        assertEq(mvh.actualSharePrice(), mvh.expectedSharePrice(), "invariant: share price");
        assertEq(mvh.actualBalance(), mvh.expectedBalance(), "invariant: vault assets balance");
        // NOTE: share price can dramatically change in some edge cases
        // assertLe(mvh.sharePriceDelta(), 100,  "invariant: share price delta"); // 1%
    }

    function invariantMaxApyVaultV2__CallSummary() public view {
        mvh.callSummary();
    }
}
