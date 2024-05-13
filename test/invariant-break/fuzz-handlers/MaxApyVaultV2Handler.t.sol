// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;
import {Test, console2} from "forge-std/Test.sol";
import {MaxApyVaultV2} from "src/MaxApyVaultV2.sol";
import {MockERC20} from "../../mock/MockERC20.sol";

contract MaxApyVaultV2Handler is Test {
    MaxApyVaultV2 vault;
    MockERC20 token;

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

    constructor(MaxApyVaultV2 _vault, MockERC20 _token) {
        vault = _vault;
        token = _token;
        token.approve(address(vault), type(uint256).max);
    }

    function deposit(uint256 amount) public {
        amount = bound(amount, 0, vault.depositLimit() - vault.totalAssets());
        if(amount == 0) return;
        
        token.mint(address(this), amount);

        expectedShares = vault.previewDeposit(amount);
        expectedTotalSupply = vault.totalSupply() + expectedShares;
        expectedTotalAssets = vault.totalAssets() + amount;
        expectedTotalDeposits = vault.totalDeposits() + amount;
        expectedTotalIdle = vault.totalDeposits() + amount;
        expectedTotalDebt = 0;
        expectedSharePrice = 10 ** token.decimals();

        actualShares = vault.deposit(amount, address(this));

        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice(); 
    }

    function redeem(uint256 shares) public {
        shares = bound(shares, 0, vault.balanceOf(address(this)));
        if(shares == 0) return;
        
        token.mint(address(this), shares);

        expectedAssets = vault.previewRedeem(shares);
        expectedTotalSupply = vault.totalSupply() - shares;
        expectedTotalAssets = vault.totalAssets() - expectedAssets;
        expectedTotalDeposits = vault.totalDeposits() - expectedAssets;
        expectedTotalIdle = vault.totalDeposits() - expectedAssets;
        expectedTotalDebt = 0;
        expectedSharePrice = (10 ** vault.decimals()) * (expectedTotalAssets + 1) / (expectedTotalSupply + 10 ** (vault.decimals() - token.decimals()));
        
        actualAssets = vault.redeem(shares, address(this), address(this));

        actualTotalSupply = vault.totalSupply();    
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice(); 
    }
}