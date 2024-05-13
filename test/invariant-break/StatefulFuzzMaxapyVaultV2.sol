// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;
import {MaxApyVaultV2Handler, MockERC20, MaxApyVaultV2}  from "./fuzz-handlers/MaxApyVaultV2Handler.t.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

contract StatefulFuzzMaxaApyVaultV2 is StdInvariant, Test {
    MaxApyVaultV2Handler mvh;

    function setUp() public {
        MockERC20 _token = new MockERC20("MockERC20", "MERC", 6);
        MaxApyVaultV2 _vault = new MaxApyVaultV2(address(_token),"MaxApyVault","max",address(1));
        mvh = new MaxApyVaultV2Handler(_vault, _token);
        targetContract(address(mvh));
    }

    function invariantMaxApyVaultV2__Deposit() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MaxApyVaultV2Handler.deposit.selector;
        targetSelector(FuzzSelector({ addr: address(mvh), selectors: selectors }));
        assertEq(mvh.expectedShares(),mvh.actualShares());
        assertEq(mvh.expectedTotalSupply(),mvh.actualTotalSupply());
        assertEq(mvh.expectedTotalIdle(),mvh.actualTotalIdle());
        assertEq(mvh.expectedTotalDebt(),mvh.actualTotalDebt());
        assertEq(mvh.expectedTotalAssets(),mvh.actualTotalAssets());
        assertEq(mvh.expectedTotalDeposits(),mvh.actualTotalDeposits());
        assertEq(mvh.expectedSharePrice(),mvh.actualSharePrice());
    }

    function invariantMaxApyVaultV2__Redeem() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MaxApyVaultV2Handler.redeem.selector;
        targetSelector(FuzzSelector({ addr: address(mvh), selectors: selectors }));
        assertLe(mvh.expectedAssets(),mvh.actualAssets());
        assertEq(mvh.expectedTotalSupply(),mvh.actualTotalSupply());
        assertGe(mvh.expectedTotalIdle(),mvh.actualTotalIdle());
        assertGe(mvh.expectedTotalDebt(),mvh.actualTotalDebt());
        assertGe(mvh.expectedTotalAssets(),mvh.actualTotalAssets());
        assertGe(mvh.expectedTotalDeposits(),mvh.actualTotalDeposits());
        assertEq(mvh.expectedSharePrice(),mvh.actualSharePrice());
    }
}