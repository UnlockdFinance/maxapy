// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseTest, IERC20, Vm, console2 } from "../base/BaseTest.t.sol";
import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";
import { MaxApyVault, StrategyData } from "src/MaxApyVault.sol";
import { MaxApyZap } from "src/MaxApyZap.sol";
import { IMaxApyZap } from "src/interfaces/IMaxApyZap.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";

import { MockStrategy } from "../mock/MockStrategy.sol";
import { MockLossyUSDCStrategy } from "../mock/MockLossyUSDCStrategy.sol";
import { MockERC777, IERC1820Registry } from "../mock/MockERC777.sol";
import { ReentrantERC777AttackerDeposit } from "../mock/ReentrantERC777AttackerDeposit.sol";
import { ReentrantERC777AttackerWithdraw } from "../mock/ReentrantERC777AttackerWithdraw.sol";
import { SigUtils } from "../utils/SigUtils.sol";
import { IERC20Permit } from "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20Metadata } from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import { WETH_MAINNET, USDC_MAINNET, _1_USDC } from "test/helpers/Tokens.sol";
import "src/helpers/AddressBook.sol";

contract MaxApyZapTest is BaseVaultTest {
    IMaxApyZap public router;
    SigUtils internal sigUtils;
    uint256 internal bobPrivateKey;

    function setUp() public {
        setupVault("MAINNET", WETH_MAINNET);
        IMaxApyZap _router = new MaxApyZap(IWrappedToken(WETH_MAINNET));
        router = IMaxApyZap(address(_router));

        IERC20(WETH_MAINNET).approve(address(router), type(uint256).max);
        vault.approve(address(router), type(uint256).max);

        vm.stopPrank();
        sigUtils = new SigUtils(IERC20Permit(USDC_MAINNET).DOMAIN_SEPARATOR());
        bobPrivateKey = 0xA11CE;
        users.bob = payable(vm.addr(bobPrivateKey));
        vm.startPrank(users.bob);
        vault.approve(address(router), type(uint256).max);

        vm.startPrank(users.eve);
        IERC20(WETH_MAINNET).approve(address(router), type(uint256).max);
        vault.approve(address(router), type(uint256).max);

        vm.startPrank(users.alice);

        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());

        vm.label(address(WETH_MAINNET), "WETH");
    }

    function generateMaxInData(uint256 shares, uint256 amount) public view returns (IMaxApyZap.MaxInData memory) {
        return IMaxApyZap.MaxInData({
            vault: IMaxApyVault(address(vault)),
            amount: amount,
            recipient: users.alice,
            minSharesOut: shares,
            router: address(0),
            assetIn: WETH_MAINNET,
            swapData: ""
        });
    }

    function generateMaxOutData(uint256 shares, uint256 amount) public view returns (IMaxApyZap.MaxOutData memory) {
       return IMaxApyZap.MaxOutData({
            vault: IMaxApyVault(address(vault)),
            shares: shares,
            recipient: users.alice,
            minAmountOut: amount,
            router: address(0),
            assetOut: WETH_MAINNET,
            swapData: ""
        }); 
    }

    function testMaxApyZap_Deposit() public {
        uint256 shares = router.maxIn(generateMaxInData(1e25, 10 ether));
        assertEq(shares, 1e25);
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.totalSupply(), 1e25);
    }

    function testMaxApyZap__MaxIn_InsufficientShares() public {
        vm.expectRevert(abi.encodeWithSignature("InsufficientShares()"));
        router.maxIn(generateMaxInData(1e25 + 1, 10 ether));
        assertEq(vault.totalDeposits(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function testMaxApyZap__MaxIn_Native() public {
        uint256 shares = router.maxInNative{ value: 10 ether }(generateMaxInData(1e25, 0 ether));
        assertEq(shares, 1e25);
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.totalSupply(), 1e25);
    }

    function testMaxApyZap__MaxIn_Native_InsufficientShares() public {
        vm.expectRevert(abi.encodeWithSignature("InsufficientShares()"));
        router.maxInNative{ value: 10 ether }(generateMaxInData(1e25 + 1, 0 ether));
        assertEq(vault.totalDeposits(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function testMaxApyZap__MaxIn_Permit() public {
        // Deploy the USDC vault
        MaxApyVault maxApyVault = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyVaultUSDC", "maxUSDCv2", TREASURY);
        IMaxApyVault _vault = IMaxApyVault(address(maxApyVault));
        deal(USDC_MAINNET, users.bob, 1000 * _1_USDC);
        vm.startPrank(users.bob);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: users.bob,
            spender: address(router),
            value: 100 * _1_USDC,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, digest);
        
        IMaxApyZap.MaxInData memory maxInData = IMaxApyZap.MaxInData({
            vault: _vault,
            amount: permit.value,
            recipient: users.bob,
            minSharesOut: 1e14,
            router: address(0),
            assetIn: USDC_MAINNET,
            swapData: ""
        });

        uint256 shares = router.maxInWithPermit(maxInData, permit.deadline, v, r, s);
        assertEq(shares, 1e14);
        assertEq(_vault.totalDeposits(), 100 * _1_USDC);
        assertEq(_vault.totalSupply(), 1e14);
    }

    function testMaxApyZap__MaxOut() public {
        router.maxIn(generateMaxInData(1e25, 10 ether));
        uint256 assets = router.maxOut(generateMaxOutData(1e25, 10 ether));
        assertEq(assets, 10 ether);
        assertEq(vault.totalDeposits(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function testMaxApyZap__MaxOut_InsufficientAssets() public {
        router.maxIn(generateMaxInData(1e25, 10 ether));
        vm.expectRevert(abi.encodeWithSignature("InsufficientAssets()"));
        router.maxOut(generateMaxOutData(1e25, 10 ether + 1));
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.totalSupply(), 1e25);
    }

    function testMaxApyZap__MaxOut_Native() public {
        router.maxIn(generateMaxInData(1e25, 10 ether));
        uint256 assets = router.maxOutNative(generateMaxOutData(1e25, 10 ether));
        assertEq(assets, 10 ether);
        assertEq(vault.totalDeposits(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function testMaxApyZap__MaxOut_Native_InsufficientAssets() public {
        router.maxIn(generateMaxInData(1e25, 10 ether));
        vm.expectRevert(abi.encodeWithSignature("InsufficientAssets()"));
        router.maxOutNative(generateMaxOutData(1e25, 10 ether + 1));
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.totalSupply(), 1e25);
    }
}
