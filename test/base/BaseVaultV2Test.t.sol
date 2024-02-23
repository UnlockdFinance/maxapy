// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {IMaxApyVaultV2} from "../../src/interfaces/IMaxApyVaultV2.sol";
import {MaxApyVaultV2, StrategyData} from "../../src/MaxApyVaultV2.sol";
import {BaseTest, IERC20, console, Vm} from "../base/BaseTest.t.sol";
import {MaxApyVaultV2Events} from "../helpers/MaxApyVaultV2Events.sol";

import {FixedPointMathLib as Math} from "solady/utils/FixedPointMathLib.sol";

contract BaseVaultV2Test is BaseTest, MaxApyVaultV2Events {
    ////////////////////////////////////////////////////////////////
    ///                      STRUCTS                             ///
    ////////////////////////////////////////////////////////////////
    struct StrategyWithdrawalPreviousData {
        uint256 balance;
        uint256 debtRatio;
        uint256 totalLoss;
        uint256 totalDebt;
    }

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IMaxApyVaultV2 public vault;
    address public TREASURY;
    uint256 public _1_USDC = 1e6;

    function setupVault() public {
        super.setUp();
        /// Fork mode activated
        TREASURY = makeAddr("treasury");
        MaxApyVaultV2 maxApyVault = new MaxApyVaultV2(USDC, "MaxApyVaultV2USDC", "maxUSDCv2", TREASURY);
        vault = IMaxApyVaultV2(address(maxApyVault));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////////////////*/
    function _deposit(address user, IMaxApyVaultV2 _vault, uint256 amount) internal returns (uint256) {
        address asset = _vault.asset();
        vm.startPrank(user);
        uint256 expectedShares = _vault.previewDeposit(amount);
        uint256 vaultBalanceBefore = IERC20(asset).balanceOf(address(vault));
        vm.expectEmit();
        emit Deposit(user, user, amount, expectedShares);
        uint256 shares = _vault.deposit(amount, user);
        assertEq(_vault.balanceOf(user), expectedShares);
        assertEq(IERC20(asset).balanceOf(address(vault)), vaultBalanceBefore + amount);

        vm.stopPrank();
        return shares;
    }

    function _withdraw(address user, IMaxApyVaultV2 _vault, uint256 assets) internal returns (uint256) {
        vm.startPrank(user);

        address asset = _vault.asset();
        uint256 userBalanceBefore = IERC20(asset).balanceOf(user);

        uint256 expectedShares = vault.previewWithdraw(assets);
        uint256 burntShares = _vault.withdraw(assets, user, user);
        uint256 withdrawn =  IERC20(asset).balanceOf(user) - userBalanceBefore;

        assertEq(withdrawn, assets);
        assertLe(burntShares, expectedShares);
        vm.stopPrank();

        return assets;
    }

    function _redeem(address user, IMaxApyVaultV2 _vault, uint256 shares, uint256 expectedLoss)
        internal
        returns (uint256)
    {
        vm.startPrank(user);

        uint256 sharesBalanceBefore = IERC20(_vault).balanceOf(user);
        uint256 sharesComputed = shares;

        uint256 expectedValue = _vault.convertToAssets(sharesComputed);
        uint256 valueWithdrawn = _vault.redeem(shares, users.alice, users.alice);
        uint256 sharesBurnt = IERC20(_vault).balanceOf(user) - sharesBalanceBefore;

        assertGe(valueWithdrawn, expectedValue);
        assertEq(shares, sharesBurnt);
        vm.stopPrank();

        return valueWithdrawn;
    }

    function _calculateExpectedShares(uint256 amount) internal view returns (uint256 shares) {
        return vault.previewDeposit(amount);
    }

    function _calculateExpectedStrategistFees(uint256 computedStrategistFee, uint256 reward, uint256 totalFee)
        internal
        pure
        returns (uint256)
    {
        return (computedStrategistFee * reward) / totalFee;
    }

    function _freeFunds() internal view returns (uint256) {
        return vault.totalAssets() - _calculateLockedProfit();
    }

    function _calculateLockedProfit() internal view returns (uint256 calculatedLockedProfit) {
        uint256 lockedFundsRatio = (block.timestamp - vault.lastReport()) * vault.lockedProfitDegradation();
        if (lockedFundsRatio < vault.DEGRADATION_COEFFICIENT()) {
            uint256 vaultLockedProfit = vault.lockedProfit();
            calculatedLockedProfit =
                vaultLockedProfit - ((lockedFundsRatio * vaultLockedProfit) / vault.DEGRADATION_COEFFICIENT());
        }
    }

    function _calculateMaxExpectedLoss(uint256 maxLoss, uint256 valueToWithdraw, uint256 totalLoss)
        internal
        pure
        returns (uint256)
    {
        return (maxLoss * (valueToWithdraw + totalLoss)) / MAX_BPS;
    }

    function _computeExpectedRatioChange(IMaxApyVaultV2 _vault, address strategy, uint256 loss)
        internal
        returns (uint256)
    {
        return Math.min((loss * _vault.debtRatio()) / _vault.totalDebt(), _vault.strategies(strategy).strategyDebtRatio);
    }
}
