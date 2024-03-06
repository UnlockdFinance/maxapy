// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {BaseTest, IERC20, Vm, console} from "../base/BaseTest.t.sol";
import {IERC20Permit} from "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import {BaseVaultV2Test} from "../base/BaseVaultV2Test.t.sol";
import {MaxApyVaultV2, StrategyData} from "src/MaxApyVaultV2.sol";
import {IMaxApyVaultV2} from "src/interfaces/IMaxApyVaultV2.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {SigUtils} from "../utils/SigUtils.sol";

contract VaultPermiTest is BaseVaultV2Test {
    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////
    SigUtils internal sigUtils;
    uint256 internal ownerPrivateKey;
    address internal owner;

    function setUp() public {
        setupVault("MAINNET");

        /// Prepare signature tests
        sigUtils = new SigUtils(IERC20Permit(USDC_MAINNET).DOMAIN_SEPARATOR());
        ownerPrivateKey = 0xA11CE;
        users.alice = payable(vm.addr(ownerPrivateKey));

        vm.startPrank(users.alice);
    }

    /// deposit 100 USDC using `permit`
    function testDepositWithPermit() public {
        deal({token: USDC_MAINNET, to: users.alice, give: 200 * _1_USDC});

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: users.alice,
            spender: address(vault),
            value: 100 * _1_USDC,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        uint256 expectedShares = vault.previewDeposit(100 * _1_USDC);

        uint256 shares = vault.depositWithPermit(users.alice, permit.value, permit.deadline, v, r, s, users.alice);
        assertEq(shares, expectedShares);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 100 * _1_USDC);
    }

    function testMintWithPermit() public {
        deal({token: USDC_MAINNET, to: users.alice, give: 200 * _1_USDC});

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: users.alice,
            spender: address(vault),
            value: 100 * _1_USDC,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        uint256 shares = vault.previewDeposit(100 * _1_USDC);
        uint256 assets = vault.mintWithPermit(users.alice, shares, permit.deadline, v, r, s, users.alice);
        assertEq(assets, 100 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 100 * _1_USDC);
    }
}
