// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {BaseTest, IERC20, Vm, console} from "../base/BaseTest.t.sol";
import {BaseVaultV2Test} from "../base/BaseVaultV2Test.t.sol";
import {MaxApyVaultV2, StrategyData} from "src/MaxApyVaultV2.sol";
import {MaxApyRouter} from "src/MaxApyRouter.sol";
import {IMaxApyRouter} from "src/interfaces/IMaxApyRouter.sol";
import {IMaxApyVaultV2} from "src/interfaces/IMaxApyVaultV2.sol";
import {IWrappedToken} from "src/interfaces/IWrappedToken.sol";

import {MockStrategy} from "../mock/MockStrategy.sol";
import {MockLossyUSDCStrategy} from "../mock/MockLossyUSDCStrategy.sol";
import {MockERC777, IERC1820Registry} from "../mock/MockERC777.sol";
import {ReentrantERC777AttackerDeposit} from "../mock/ReentrantERC777AttackerDeposit.sol";
import {ReentrantERC777AttackerWithdraw} from "../mock/ReentrantERC777AttackerWithdraw.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract MaxApyRouterTest is BaseVaultV2Test {
    IMaxApyRouter public router;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////
    function setUp() public {
        setupVault("MAINNET", WETH_MAINNET);
        /// Deploy  MaxApy router
        MaxApyRouter _router = new MaxApyRouter(IWrappedToken(WETH_MAINNET));
        router = IMaxApyRouter(address(_router));

        /// Alice approval
        IERC20(WETH_MAINNET).approve(address(router), type(uint256).max);
        vault.approve(address(router), type(uint256).max);

        vm.stopPrank();
        /// Bob approval
        vm.startPrank(users.bob);
        IERC20(WETH_MAINNET).approve(address(router), type(uint256).max);
        vault.approve(address(router), type(uint256).max);

        /// Eve approval
        vm.startPrank(users.eve);
        IERC20(WETH_MAINNET).approve(address(router), type(uint256).max);
        vault.approve(address(router), type(uint256).max);

        vm.startPrank(users.alice);

        /// Grant extra emergency admin role to alice
        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());

        vm.label(address(WETH_MAINNET), "WETH");
    }

    ////////////////////////////////////////////////////////////////
    ///                      Test deposit(                       ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyRouter__Deposit() public {
        router.deposit(vault, 10 ether, users.alice, 1e25);
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.totalSupply(), 1e25);
    }

    function testMaxApyRouter__Deposit_InsufficientShares() public {
        vm.expectRevert(abi.encodeWithSignature("InsufficientShares()"));
        router.deposit(vault, 10 ether, users.alice, 1e25 + 1);
        assertEq(vault.totalDeposits(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function testMaxApyRouter__Deposit_Native() public {
        router.depositNative{value:10 ether}(vault, users.alice, 1e25);
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.totalSupply(), 1e25);
    }

    function testMaxApyRouter__Deposit_Native_InsufficientShares() public {
        vm.expectRevert(abi.encodeWithSignature("InsufficientShares()"));
        router.depositNative{value:10 ether}(vault, users.alice, 1e25 +1);
        assertEq(vault.totalDeposits(), 0);
        assertEq(vault.totalSupply(), 0 );
    }

    ////////////////////////////////////////////////////////////////
    ///                      Test redeem()                        ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyRouter__Redeem() public {
        router.deposit(vault, 10 ether, users.alice, 1e25);  
        router.redeem(vault, 1e25, users.alice, 10 ether);
        assertEq(vault.totalDeposits(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function testMaxApyRouter__Redeem_InsufficientAssets() public {
        router.deposit(vault, 10 ether, users.alice, 1e25);  
        vm.expectRevert(abi.encodeWithSignature("InsufficientAssets()"));
        router.redeem(vault, 1e25, users.alice, 10 ether + 1);
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.totalSupply(), 1e25);
    }
}
