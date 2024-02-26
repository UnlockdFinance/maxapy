// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {BaseTest, IERC20, Vm, console} from "../base/BaseTest.t.sol";
import {BaseVaultV2Test} from "../base/BaseVaultV2Test.t.sol";
import {MaxApyVaultV2, StrategyData} from "src/MaxApyVaultV2.sol";
import {IMaxApyVaultV2} from "src/interfaces/IMaxApyVaultV2.sol";

import {MockStrategy} from "../mock/MockStrategy.sol";
import {MockLossyUSDCStrategy} from "../mock/MockLossyUSDCStrategy.sol";
import {MockERC777, IERC1820Registry} from "../mock/MockERC777.sol";
import {ReentrantERC777AttackerDeposit} from "../mock/ReentrantERC777AttackerDeposit.sol";
import {ReentrantERC777AttackerWithdraw} from "../mock/ReentrantERC777AttackerWithdraw.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract MaxApyVaultV2Test is BaseVaultV2Test {
    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function setUp() public override {
        setupVault();

        /// Alice approval
        IERC20(USDC).approve(address(vault), type(uint256).max);
        vm.stopPrank();
        /// Bob approval
        vm.startPrank(users.bob);
        IERC20(USDC).approve(address(vault), type(uint256).max);

        /// Eve approval
        vm.startPrank(users.eve);
        IERC20(USDC).approve(address(vault), type(uint256).max);

        vm.startPrank(users.alice);

        /// Grant extra emergency admin role to alice
        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());

        vm.label(address(USDC), "USDC");
    }

    /*==================INITIALIZATION TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///                  TEST initialize()                       ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__Initialization() public {
        /// *************** MaxApyVault initialization *************** ///

        /// Ensure performance fee is set to the number defined in initialization (1000)
        assertEq(vault.performanceFee(), 1000);

        /// Ensure management fee is set to the number defined in initialization (200)
        assertEq(vault.managementFee(), 200);

        /// *************** BaseVault initialization *************** ///

        /// Ensure underlying is the initialized asset
        assertEq(address(vault.asset()), USDC);

        /// *************** ERC20Upgradeable initialization *************** ///

        /// Ensure the vault name is correct
        assertEq(vault.name(), "MaxApyVaultV2USDC");
        /// Ensure the vault symbol is correct
        assertEq(vault.symbol(), "maxUSDCv2");
        /// Ensure underlying decimals is the initialized asset decimals
        assertEq(vault.decimals(), IERC20Metadata(USDC).decimals() + 6);
    }

    /*==================ACCESS CONTROL TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///                    TEST OWNER NEGATIVES                  ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__OwnerNegatives() public {
        /// *************** 🔹 Setup 🔹 *************** ///
        MaxApyVaultV2 maxApyVault = new MaxApyVaultV2(USDC, "MaxApyVaultV2USDC", "maxUSDCv2", TREASURY);

        IMaxApyVaultV2 vaultOwnership = IMaxApyVaultV2(address(maxApyVault));
        assertEq(vaultOwnership.owner(), users.alice);

        /// *************** Transfer ownership *************** ///

        /// Transfer ownership to 0 address
        vm.expectRevert(abi.encodeWithSignature("NewOwnerIsZeroAddress()"));
        vaultOwnership.transferOwnership(address(0));

        /// User who is not owner tries to transfer ownership
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vaultOwnership.transferOwnership(address(0));

        /// *************** Renounce ownership *************** ///

        /// User who is not owner tries to renounce ownership
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vaultOwnership.renounceOwnership();

        /// *************** Complete ownership handover *************** ///

        /// User who is not owner tries to complete ownership handover
        vaultOwnership.requestOwnershipHandover();
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vaultOwnership.completeOwnershipHandover(users.bob);

        /// Ownership handover expires
        vaultOwnership.requestOwnershipHandover();
        vm.warp(block.timestamp + vaultOwnership.ownershipHandoverValidFor() + 1);
        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("NoHandoverRequest()"));
        vaultOwnership.completeOwnershipHandover(users.bob);

        /// Ownership handover does not exist
        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("NoHandoverRequest()"));
        vaultOwnership.completeOwnershipHandover(users.eve);
    }

    ////////////////////////////////////////////////////////////////
    ///                    TEST OWNER POSITIVES                  ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__OwnerPositives() public {
        /// *************** 🔹 Setup 🔹 *************** ///
        MaxApyVaultV2 maxApyVault = new MaxApyVaultV2(USDC, "MaxApyVaultV2USDC", "maxUSDCv2", TREASURY);

        IMaxApyVaultV2 vaultOwnership = IMaxApyVaultV2(address(maxApyVault));
        assertEq(vaultOwnership.owner(), users.alice);

        /// *************** Transfer ownership *************** ///

        /// Transfer ownership from alice to bob
        vm.expectEmit();
        emit OwnershipTransferred(users.alice, users.bob);
        vaultOwnership.transferOwnership(users.bob);
        assertEq(vaultOwnership.owner(), users.bob);

        /// Transfer ownership back from bob to alice
        vm.startPrank(users.bob);
        vm.expectEmit();
        emit OwnershipTransferred(users.bob, users.alice);
        vaultOwnership.transferOwnership(users.alice);
        assertEq(vaultOwnership.owner(), users.alice);

        /// *************** Request/cancel/accept ownership handover *************** ///

        /// Bob requests ownership handover
        vm.expectEmit();
        emit OwnershipHandoverRequested(users.bob);
        vaultOwnership.requestOwnershipHandover();
        assertEq(
            vaultOwnership.ownershipHandoverExpiresAt(users.bob),
            block.timestamp + vaultOwnership.ownershipHandoverValidFor()
        );

        /// Bob cancels ownership handover
        vm.expectEmit();
        emit OwnershipHandoverCanceled(users.bob);
        vaultOwnership.cancelOwnershipHandover();
        assertEq(vaultOwnership.ownershipHandoverExpiresAt(users.bob), 0);

        /// Bob requests ownership handover and owner(alice) accepts it
        vm.expectEmit();
        emit OwnershipHandoverRequested(users.bob);
        vaultOwnership.requestOwnershipHandover();
        assertEq(
            vaultOwnership.ownershipHandoverExpiresAt(users.bob),
            block.timestamp + vaultOwnership.ownershipHandoverValidFor()
        );

        vm.startPrank(users.alice);
        vm.expectEmit();
        emit OwnershipTransferred(users.alice, users.bob);
        vaultOwnership.completeOwnershipHandover(users.bob);
        assertEq(vaultOwnership.ownershipHandoverExpiresAt(users.bob), 0);
        assertEq(vaultOwnership.owner(), users.bob);

        /// Alice requests ownership handover, time passes until prior of ownership request expiry, and owner(bob) accepts it
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit OwnershipHandoverRequested(users.alice);
        vaultOwnership.requestOwnershipHandover();
        assertEq(
            vaultOwnership.ownershipHandoverExpiresAt(users.alice),
            block.timestamp + vaultOwnership.ownershipHandoverValidFor()
        );

        vm.warp(block.timestamp + vaultOwnership.ownershipHandoverValidFor());

        vm.startPrank(users.bob);
        vm.expectEmit();
        emit OwnershipTransferred(users.bob, users.alice);
        vaultOwnership.completeOwnershipHandover(users.alice);
        assertEq(vaultOwnership.ownershipHandoverExpiresAt(users.alice), 0);
        assertEq(vaultOwnership.owner(), users.alice);

        /// *************** Renounce ownership *************** ///

        /// Renounce ownership
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit OwnershipTransferred(users.alice, address(0));
        vaultOwnership.renounceOwnership();
        assertEq(vaultOwnership.owner(), address(0));
    }

    ////////////////////////////////////////////////////////////////
    ///                    TEST ROLES NEGATIVES                  ///
    ////////////////////////////////////////////////////////////////
    function testMaxApyVaultV2__RolesNegatives() public {
        /// *************** 🔹 Setup 🔹 *************** ///

        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC);

        MaxApyVaultV2 maxApyVault = new MaxApyVaultV2(USDC, "MaxApyVaultV2USDC", "maxUSDCv2", TREASURY);

        IMaxApyVaultV2 vaultRoles = IMaxApyVaultV2(address(maxApyVault));

        uint256 ADMIN_ROLE = vaultRoles.ADMIN_ROLE();
        uint256 EMERGENCY_ADMIN_ROLE = vaultRoles.EMERGENCY_ADMIN_ROLE();

        /// ROLE DISTRIBUTION:
        ///     - ALICE -> OWNER, ADMIN
        ///     - BOB -> ADMIN
        ///     - CHARLIE -> EMERGENCY ADMIN
        ///     - EVE -> NO ROLE

        vaultRoles.grantRoles(users.bob, ADMIN_ROLE);
        vaultRoles.grantRoles(users.charlie, EMERGENCY_ADMIN_ROLE);

        /// Check alice's roles
        assertEq(vaultRoles.owner(), users.alice);
        assertEq(vaultRoles.hasAnyRole(users.alice, ADMIN_ROLE), true);
        /// Check bob's roles
        assertEq(vaultRoles.hasAnyRole(users.bob, ADMIN_ROLE), true);
        /// Check charlie's roles
        assertEq(vaultRoles.hasAnyRole(users.charlie, EMERGENCY_ADMIN_ROLE), true);

        /// *************** Grant roles *************** ///

        /// User not owner tries to grant roles
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vaultRoles.grantRoles(users.eve, ADMIN_ROLE);

        /// *************** Revoke roles *************** ///

        /// User not owner tries to revoke roles
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vaultRoles.revokeRoles(users.alice, ADMIN_ROLE);

        /// *************** Function capped by only `ADMIN` role *************** ///

        /// Try with a user without roles
        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.addStrategy(address(mockStrategy), 4000, 0, 0, 0);

        /// Try with a user with `EMERGENCY_ADMIN` role
        vm.startPrank(users.charlie);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.addStrategy(address(mockStrategy), 4000, 0, 0, 0);

        /// *************** Function capped by only `EMERGENCY_ADMIN` role *************** ///

        /// Try with a user without roles
        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setEmergencyShutdown(true);

        /// Try with a user with `ADMIN` role
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setEmergencyShutdown(true);

        /// Try with a user with `OWNER` role
        vm.startPrank(users.alice);
        vault.revokeRoles(users.alice, EMERGENCY_ADMIN_ROLE);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setEmergencyShutdown(true);

        /// Give back emergency admin role to alice
        vault.grantRoles(users.alice, EMERGENCY_ADMIN_ROLE);
    }

    ////////////////////////////////////////////////////////////////
    ///                    TEST ROLES POSITIVES                  ///
    ////////////////////////////////////////////////////////////////
    function testMaxApyVaultV2__RolesPositives() public {
        /// *************** 🔹 Setup 🔹 *************** ///

        MaxApyVaultV2 maxApyVault = new MaxApyVaultV2(USDC, "MaxApyVaultV2USDC", "maxUSDCv2", TREASURY);

        IMaxApyVaultV2 vaultRoles = IMaxApyVaultV2(address(maxApyVault));

        MockStrategy mockStrategy = new MockStrategy(address(vaultRoles), USDC);

        uint256 ADMIN_ROLE = vaultRoles.ADMIN_ROLE();
        uint256 EMERGENCY_ADMIN_ROLE = vaultRoles.EMERGENCY_ADMIN_ROLE();

        /// ROLE DISTRIBUTION:
        ///     - ALICE -> OWNER, ADMIN, EMERGENCY ADMIN
        ///     - BOB -> ADMIN
        ///     - CHARLIE -> EMERGENCY ADMIN
        ///     - EVE -> NO ROLE

        vaultRoles.grantRoles(users.alice, EMERGENCY_ADMIN_ROLE);
        vaultRoles.grantRoles(users.bob, ADMIN_ROLE);
        vaultRoles.grantRoles(users.charlie, EMERGENCY_ADMIN_ROLE);

        /// Check alice's roles
        assertEq(vaultRoles.owner(), users.alice);
        assertEq(vaultRoles.hasAnyRole(users.alice, ADMIN_ROLE), true);
        assertEq(vaultRoles.hasAnyRole(users.alice, EMERGENCY_ADMIN_ROLE), true);
        /// Check bob's roles
        assertEq(vaultRoles.hasAnyRole(users.bob, ADMIN_ROLE), true);
        /// Check charlie's roles
        assertEq(vaultRoles.hasAnyRole(users.charlie, EMERGENCY_ADMIN_ROLE), true);

        /// *************** Grant roles *************** ///

        /// Owner tries to grant `ADMIN_ROLE`
        vm.expectEmit();
        emit RolesUpdated(users.eve, ADMIN_ROLE);
        vaultRoles.grantRoles(users.eve, ADMIN_ROLE);

        /// Owner tries to grant `EMERGENCY_ADMIN_ROLE`
        uint256 expectedRoles;
        assembly {
            expectedRoles := or(ADMIN_ROLE, EMERGENCY_ADMIN_ROLE)
        }
        vm.expectEmit();
        emit RolesUpdated(users.eve, expectedRoles);
        vaultRoles.grantRoles(users.eve, EMERGENCY_ADMIN_ROLE);

        /// *************** Revoke roles *************** ///

        /// Owner tries to revoke `ADMIN_ROLE`
        vm.expectEmit();
        emit RolesUpdated(users.eve, EMERGENCY_ADMIN_ROLE);
        /// Only `EMERGENCY_ADMIN_ROLE` will be left for eve
        vaultRoles.revokeRoles(users.eve, ADMIN_ROLE);

        /// Owner tries to revoke `EMERGENCY_ADMIN_ROLE`
        vm.expectEmit();
        emit RolesUpdated(users.eve, 0);
        /// No roles left for eve
        vaultRoles.revokeRoles(users.eve, EMERGENCY_ADMIN_ROLE);

        /// *************** Bob renounces to `ADMIN_ROLE` role *************** ///
        vm.startPrank(users.bob);
        vm.expectEmit();
        emit RolesUpdated(users.bob, 0);
        /// No roles left for bob
        vaultRoles.renounceRoles(ADMIN_ROLE);

        // /// *************** Function capped by only `ADMIN_ROLE` role *************** ///

        /// Try with alice
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit StrategyAdded(address(mockStrategy), 4000, 0, 0, 0);
        vaultRoles.addStrategy(address(mockStrategy), 4000, 0, 0, 0);

        /// Try with bob
        mockStrategy = new MockStrategy(address(vaultRoles), USDC);
        vaultRoles.grantRoles(users.bob, ADMIN_ROLE);
        vm.startPrank(users.bob);
        vm.expectEmit();
        emit StrategyAdded(address(mockStrategy), 4000, 0, 0, 0);
        vaultRoles.addStrategy(address(mockStrategy), 4000, 0, 0, 0);

        /// *************** Function capped by only `EMERGENCY_ADMIN` role *************** ///

        /// Try with alice
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit EmergencyShutdownUpdated(false);
        vaultRoles.setEmergencyShutdown(false);

        /// Try with charlie
        vm.startPrank(users.charlie);
        vm.expectEmit();
        emit EmergencyShutdownUpdated(false);
        vaultRoles.setEmergencyShutdown(false);
    }

    /*==================STRATEGIES CONFIGURATION TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///               TEST addStrategy() NEGATIVES               ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__AddStrategyNegatives() public {
        /// *************** 🔹 Setup 🔹 *************** ///
        MaxApyVaultV2 maxApyVault = new MaxApyVaultV2(USDC, "MaxApyVaultV2USDC", "maxUSDCv2", TREASURY);

        IMaxApyVaultV2 fullQueueVault = IMaxApyVaultV2(address(maxApyVault));

        MockStrategy mockStrategy = new MockStrategy(address(fullQueueVault), USDC);
        /// *************** General vault checks *************** ///

        /// Queue is full
        for (uint256 i; i < vault.MAXIMUM_STRATEGIES();) {
            /// Add 20 strategies. Fill queue.
            mockStrategy = new MockStrategy(address(fullQueueVault), USDC);
            fullQueueVault.addStrategy(address(mockStrategy), 0, 0, 0, 0);
            unchecked {
                ++i;
            }
        }

        mockStrategy = new MockStrategy(address(fullQueueVault), USDC);
        vm.expectRevert(abi.encodeWithSignature("QueueIsFull()"));
        fullQueueVault.addStrategy(address(mockStrategy), 0, 0, 0, 0);

        mockStrategy = new MockStrategy(address(vault), USDC);

        /// Prepare strategy for next tests

        /// Vault is in emergency shutdown
        vault.setEmergencyShutdown(true);
        vm.expectRevert(abi.encodeWithSignature("VaultInEmergencyShutdownMode()"));
        vault.addStrategy(address(mockStrategy), 0, 0, 0, 0);
        vault.setEmergencyShutdown(false);

        /// *************** Strategy checks *************** ///

        /// Strategy is address(0)
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAddress()"));
        vault.addStrategy(address(0), 0, 0, 0, 0);

        /// Strategy is already active
        vault.addStrategy(address(mockStrategy), 0, 0, 0, 0);
        vm.expectRevert(abi.encodeWithSignature("StrategyAlreadyActive()"));
        vault.addStrategy(address(mockStrategy), 0, 0, 0, 0);

        /// Invalid strategy vault
        mockStrategy = new MockStrategy(address(0), USDC);
        vm.expectRevert(abi.encodeWithSignature("InvalidStrategyVault()"));
        vault.addStrategy(address(mockStrategy), 0, 0, 0, 0);

        /// Invalid strategy underlying
        mockStrategy = new MockStrategy(address(vault), address(0));
        vm.expectRevert(abi.encodeWithSignature("InvalidStrategyUnderlying()"));
        vault.addStrategy(address(mockStrategy), 0, 0, 0, 0);

        /// Invalid strategy strategist
        mockStrategy = new MockStrategy(address(vault), USDC);
        mockStrategy.setStrategist(address(0));
        vm.expectRevert(abi.encodeWithSignature("StrategyMustHaveStrategist()"));
        vault.addStrategy(address(mockStrategy), 0, 0, 0, 0);

        /// *************** Configuration checks *************** ///
        mockStrategy = new MockStrategy(address(vault), USDC);

        /// Check `debtRatio + strategyDebtRatio` > MAX_BPS
        vm.expectRevert(abi.encodeWithSignature("InvalidDebtRatio()"));
        vault.addStrategy(address(mockStrategy), 10_001, 0, 0, 0);

        MaxApyVaultV2 maxApyVault2 = new MaxApyVaultV2(
            /// Deploy new instance to add debt ratio and test addition
            USDC,
            "MaxApyVaultV2USDC",
            "maxUSDCv2",
            TREASURY
        );

        IMaxApyVaultV2 debtRatioVault = IMaxApyVaultV2(address(maxApyVault2));

        mockStrategy = new MockStrategy(address(debtRatioVault), USDC);

        /// Set vault in strategy to new instance

        debtRatioVault.addStrategy(address(mockStrategy), 5600, 0, 0, 0);

        /// Add one strategy correctly, with a valid debt ratio
        mockStrategy = new MockStrategy(address(debtRatioVault), USDC);
        vm.expectRevert(abi.encodeWithSignature("InvalidDebtRatio()"));
        debtRatioVault.addStrategy(address(mockStrategy), 4401, 0, 0, 0);
        /// Check `debtRatio + strategyDebtRatio > MAX_BPS` works

        mockStrategy = new MockStrategy(address(vault), USDC);

        /// Go back to normal strategy
        /// Check `strategyMinDebtPerHarvest` > `strategyMaxDebtPerHarvest`
        vm.expectRevert(abi.encodeWithSignature("InvalidMinDebtPerHarvest()"));
        vault.addStrategy(address(mockStrategy), 10_000, 1_000_000, 1_000_001, 0);

        vm.expectRevert(abi.encodeWithSignature("InvalidMinDebtPerHarvest()"));
        vault.addStrategy(address(mockStrategy), 10_000, 0, 1, 0);

        /// Check `strategyPerformanceFee` > 5_000
        vm.expectRevert(abi.encodeWithSignature("InvalidPerformanceFee()"));
        vault.addStrategy(address(mockStrategy), 10_000, 10, 1, 5001);

        vm.expectRevert(abi.encodeWithSignature("InvalidPerformanceFee()"));
        vault.addStrategy(address(mockStrategy), 10_000, 10, 1, 10_000);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST addStrategy() POSITIVES               ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__AddStrategyPositives() public {
        /// *************** 🔹 Setup 🔹 *************** ///
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC);
        assertEq(vault.MAXIMUM_STRATEGIES(), 20);
        address[] memory totalStrategies = new address[](20);
        /// *************** 🔸 Tests 🔸 *************** ///

        /// Add first strategy
        vm.expectEmit();
        emit StrategyAdded(address(mockStrategy), 6000, type(uint72).max, 0, 4000);
        vault.addStrategy(
            address(mockStrategy),
            /// strategy address
            6000,
            /// strategyDebtRatio
            type(uint72).max,
            /// strategyMaxDebtPerHarvest
            0,
            /// strategyMinDebtPerHarvest
            4000
        );
        /// strategyPerformanceFee

        StrategyData memory strategyData = vault.strategies(address(mockStrategy));
        assertEq(strategyData.strategyDebtRatio, 6000);
        assertEq(strategyData.strategyMaxDebtPerHarvest, type(uint72).max);
        assertEq(strategyData.strategyMinDebtPerHarvest, 0);
        assertEq(strategyData.strategyPerformanceFee, 4000);
        assertEq(strategyData.strategyLastReport, block.timestamp);
        assertEq(strategyData.strategyActivation, block.timestamp);
        assertEq(strategyData.strategyTotalDebt, 0);
        assertEq(strategyData.strategyTotalRealizedGain, 0);
        assertEq(strategyData.strategyTotalLoss, 0);

        assertEq(vault.debtRatio(), 6000);
        assertEq(vault.withdrawalQueue(0), address(mockStrategy));

        totalStrategies[0] = address(mockStrategy);

        /// Add second strategy
        mockStrategy = new MockStrategy(address(vault), USDC);

        vm.expectEmit();
        emit StrategyAdded(address(mockStrategy), 20, type(uint72).max, type(uint24).max, 5000);
        vault.addStrategy(
            address(mockStrategy),
            /// strategy address
            20,
            /// strategyDebtRatio
            type(uint72).max,
            /// strategyMaxDebtPerHarvest
            type(uint24).max,
            /// strategyMinDebtPerHarvest
            5000
        );
        /// strategyPerformanceFee

        strategyData = vault.strategies(address(mockStrategy));
        assertEq(strategyData.strategyDebtRatio, 20);
        assertEq(strategyData.strategyMaxDebtPerHarvest, type(uint72).max);
        assertEq(strategyData.strategyMinDebtPerHarvest, type(uint24).max);
        assertEq(strategyData.strategyPerformanceFee, 5000);
        assertEq(strategyData.strategyLastReport, block.timestamp);
        assertEq(strategyData.strategyActivation, block.timestamp);
        assertEq(strategyData.strategyTotalDebt, 0);
        assertEq(strategyData.strategyTotalRealizedGain, 0);
        assertEq(strategyData.strategyTotalLoss, 0);

        assertEq(vault.debtRatio(), 6020);
        assertEq(vault.withdrawalQueue(1), address(mockStrategy));

        totalStrategies[1] = address(mockStrategy);

        /// Add third strategy
        mockStrategy = new MockStrategy(address(vault), USDC);

        vm.expectEmit();
        emit StrategyAdded(address(mockStrategy), 3980, 0, 0, 488);
        vault.addStrategy(
            address(mockStrategy),
            /// strategy address
            3980,
            /// strategyDebtRatio
            0,
            /// strategyMaxDebtPerHarvest
            0,
            /// strategyMinDebtPerHarvest
            488
        );
        /// strategyPerformanceFee

        strategyData = vault.strategies(address(mockStrategy));
        assertEq(strategyData.strategyDebtRatio, 3980);
        assertEq(strategyData.strategyMaxDebtPerHarvest, 0);
        assertEq(strategyData.strategyMinDebtPerHarvest, 0);
        assertEq(strategyData.strategyPerformanceFee, 488);
        assertEq(strategyData.strategyLastReport, block.timestamp);
        assertEq(strategyData.strategyActivation, block.timestamp);
        assertEq(strategyData.strategyTotalDebt, 0);
        assertEq(strategyData.strategyTotalRealizedGain, 0);
        assertEq(strategyData.strategyTotalLoss, 0);

        assertEq(vault.debtRatio(), 10_000);
        assertEq(vault.withdrawalQueue(2), address(mockStrategy));

        totalStrategies[2] = address(mockStrategy);

        /// Ensure strategies were properly added
        assertEq(totalStrategies[0], vault.withdrawalQueue(0));
        assertEq(totalStrategies[1], vault.withdrawalQueue(1));
        assertEq(totalStrategies[2], vault.withdrawalQueue(2));
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST revokeStrategy()                      ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__RevokeStrategy() public {
        /// *************** 🔹 Setup 🔹 *************** ///

        MockStrategy mockStrategyNegatives = new MockStrategy(address(vault), USDC);
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC);

        /// *************** Negatives *************** ///

        /// Revoking non-existent strategy (debt ratio is 0)
        vm.expectRevert(abi.encodeWithSignature("StrategyDebtRatioAlreadyZero()"));
        vault.revokeStrategy(address(mockStrategyNegatives));

        /// Revoking strategy already revoked
        vault.addStrategy(address(mockStrategyNegatives), 4000, 0, 0, 0);
        vault.revokeStrategy(address(mockStrategyNegatives));
        vm.expectRevert(abi.encodeWithSignature("StrategyDebtRatioAlreadyZero()"));
        vault.revokeStrategy(address(mockStrategyNegatives));

        /// *************** Positives *************** ///
        vault.addStrategy(address(mockStrategy), 4000, 0, 0, 0);
        assertEq(vault.debtRatio(), 4000);
        vm.expectEmit();
        emit StrategyRevoked(address(mockStrategy));
        vault.revokeStrategy(address(mockStrategy));
        assertEq(vault.debtRatio(), 0);
        StrategyData memory strategyData = vault.strategies(address(mockStrategy));
        assertEq(vault.debtRatio(), 0);
        assertEq(strategyData.strategyDebtRatio, 0);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST removeStrategy()                      ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__RemoveStrategy() public {
        /// *************** 🔹 Setup 🔹 *************** ///

        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC);
        MockStrategy mockStrategy2 = new MockStrategy(address(vault), USDC);
        MockStrategy mockStrategy3 = new MockStrategy(address(vault), USDC);
        MockStrategy mockStrategy4 = new MockStrategy(address(vault), USDC);
        MockStrategy mockStrategy5 = new MockStrategy(address(vault), USDC);
        MockStrategy mockStrategy6 = new MockStrategy(address(vault), USDC);

        vault.addStrategy(address(mockStrategy), 2000, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy2), 200, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy3), 2000, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy4), 20, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy5), 200, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy6), 20, type(uint72).max, 0, 100);

        /// *************** Negatives *************** ///

        /// Unauthorized removal
        changePrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.revokeStrategy(address(0));

        /// *************** Positives *************** ///
        changePrank(users.alice);
        /// No strategy is removed passing an address not registered
        vault.removeStrategy(makeAddr("1"));

        /// Strategy 4 is removed
        vault.removeStrategy(address(mockStrategy4));

        assertEq(vault.withdrawalQueue(0), address(mockStrategy));
        assertEq(vault.withdrawalQueue(1), address(mockStrategy2));
        assertEq(vault.withdrawalQueue(2), address(mockStrategy3));
        assertEq(vault.withdrawalQueue(3), address(mockStrategy5));
        assertEq(vault.withdrawalQueue(4), address(mockStrategy6));

        /// Strategy 1, 2 and 5 are removed
        vault.removeStrategy(address(mockStrategy));
        vault.removeStrategy(address(mockStrategy2));
        vault.removeStrategy(address(mockStrategy5));

        assertEq(vault.withdrawalQueue(0), address(mockStrategy3));
        assertEq(vault.withdrawalQueue(1), address(mockStrategy6));
        assertEq(vault.withdrawalQueue(2), address(0));
    }

    ////////////////////////////////////////////////////////////////
    ///            TEST updateStrategyData() NEGATIVES           ///
    ////////////////////////////////////////////////////////////////
    function testMaxApyVaultV2__UpdateStrategyDataNegatives() public {
        /// *************** 🔹 Setup 🔹 *************** ///
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC);
        MockStrategy mockStrategy2 = new MockStrategy(address(vault), USDC);

        vault.addStrategy(address(mockStrategy), 4000, 0, 0, 3000);

        /// *************** 🔸 Tests 🔸 *************** ///

        /// Test strategy not active
        vm.expectRevert(abi.encodeWithSignature("StrategyNotActive()"));
        vault.updateStrategyData(address(mockStrategy2), 4000, 0, 0, 3000);

        /// Test strategy is in emergency exit mode
        mockStrategy.setEmergencyExit(2);
        vm.expectRevert(abi.encodeWithSignature("StrategyInEmergencyExitMode()"));
        vault.updateStrategyData(address(mockStrategy), 4000, 0, 0, 3000);
        mockStrategy.setEmergencyExit(1);

        /// Test `newMinDebtPerHarvest` > `newMaxDebtPerHarvest`
        vm.expectRevert(abi.encodeWithSignature("InvalidMinDebtPerHarvest()"));
        vault.updateStrategyData(
            address(mockStrategy),
            4000,
            0,
            /// newMaxDebtPerHarvest
            1,
            /// newMinDebtPerHarvest
            3000
        );

        /// Test invalid performance fee
        vm.expectRevert(abi.encodeWithSignature("InvalidPerformanceFee()"));
        vault.updateStrategyData(address(mockStrategy), 4000, 0, 0, 5001);
        /// performance fee

        /// Test invalid debt ratio
        vm.expectRevert(abi.encodeWithSignature("InvalidDebtRatio()"));
        vault.updateStrategyData(
            address(mockStrategy),
            10_001,
            /// Debt ratio
            0,
            0,
            5000
        );

        MockStrategy mockStrategy3 = new MockStrategy(address(vault), USDC);
        /// Add strategy. Initial debt ratio + new strategy debt ratio = 4000 + 2000 = 6000
        vault.addStrategy(address(mockStrategy3), 2000, 0, 0, 3000);

        vm.expectRevert(abi.encodeWithSignature("InvalidDebtRatio()"));
        vault.updateStrategyData(
            address(mockStrategy),
            8_001,
            /// Debt ratio
            0,
            0,
            5000
        );
    }

    ////////////////////////////////////////////////////////////////
    ///            TEST updateStrategyData() POSITIVES           ///
    ////////////////////////////////////////////////////////////////
    function testMaxApyVaultV2__UpdateStrategyDataPositives() public {
        /// *************** 🔹 Setup 🔹 *************** ///
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC);
        MockStrategy mockStrategy2 = new MockStrategy(address(vault), USDC);

        MockStrategy mockStrategy3 = new MockStrategy(address(vault), USDC);

        vault.addStrategy(address(mockStrategy), 4000, 0, 0, 3000);
        vault.addStrategy(address(mockStrategy2), 3000, 0, 0, 299);
        vault.addStrategy(address(mockStrategy3), 2000, 0, 0, 5000);

        assertEq(vault.debtRatio(), 9000);

        StrategyData memory mockStrategyDataBefore = vault.strategies(address(mockStrategy));
        StrategyData memory mockStrategy2DataBefore = vault.strategies(address(mockStrategy2));
        StrategyData memory mockStrategy3DataBefore = vault.strategies(address(mockStrategy3));

        /// *************** 🔸 Tests 🔸 *************** ///

        /// Update first strategy
        vault.updateStrategyData(address(mockStrategy), 5000, type(uint72).max, type(uint24).max, 100);

        StrategyData memory mockStrategyData = vault.strategies(address(mockStrategy));
        assertEq(mockStrategyData.strategyDebtRatio, 5000);
        assertEq(mockStrategyData.strategyMaxDebtPerHarvest, type(uint72).max);
        assertEq(mockStrategyData.strategyMinDebtPerHarvest, type(uint24).max);
        assertEq(mockStrategyData.strategyPerformanceFee, 100);
        assertEq(mockStrategyData.strategyLastReport, mockStrategyDataBefore.strategyLastReport);
        assertEq(mockStrategyData.strategyActivation, mockStrategyDataBefore.strategyActivation);
        assertEq(mockStrategyData.strategyTotalDebt, 0);
        assertEq(mockStrategyData.strategyTotalRealizedGain, 0);
        assertEq(mockStrategyData.strategyTotalLoss, 0);

        assertEq(
            vault.debtRatio(),
            5000 + mockStrategy2DataBefore.strategyDebtRatio + mockStrategy3DataBefore.strategyDebtRatio
        );

        /// Update second strategy
        vault.updateStrategyData(address(mockStrategy2), 100, 200, 10, 4999);

        StrategyData memory mockStrategyData2 = vault.strategies(address(mockStrategy2));
        assertEq(mockStrategyData2.strategyDebtRatio, 100);
        assertEq(mockStrategyData2.strategyMaxDebtPerHarvest, 200);
        assertEq(mockStrategyData2.strategyMinDebtPerHarvest, 10);
        assertEq(mockStrategyData2.strategyPerformanceFee, 4999);
        assertEq(mockStrategyData2.strategyLastReport, mockStrategy2DataBefore.strategyLastReport);
        assertEq(mockStrategyData2.strategyActivation, mockStrategy2DataBefore.strategyActivation);
        assertEq(mockStrategyData2.strategyTotalDebt, 0);
        assertEq(mockStrategyData2.strategyTotalRealizedGain, 0);
        assertEq(mockStrategyData2.strategyTotalLoss, 0);

        assertEq(vault.debtRatio(), 5000 + 100 + mockStrategy3DataBefore.strategyDebtRatio);

        /// Update third strategy
        vault.updateStrategyData(address(mockStrategy3), 4786, 1999, 45, 1);

        StrategyData memory mockStrategyData3 = vault.strategies(address(mockStrategy3));
        assertEq(mockStrategyData3.strategyDebtRatio, 4786);
        assertEq(mockStrategyData3.strategyMaxDebtPerHarvest, 1999);
        assertEq(mockStrategyData3.strategyMinDebtPerHarvest, 45);
        assertEq(mockStrategyData3.strategyPerformanceFee, 1);
        assertEq(mockStrategyData3.strategyLastReport, mockStrategy3DataBefore.strategyLastReport);
        assertEq(mockStrategyData3.strategyActivation, mockStrategy3DataBefore.strategyActivation);
        assertEq(mockStrategyData3.strategyTotalDebt, 0);
        assertEq(mockStrategyData3.strategyTotalRealizedGain, 0);
        assertEq(mockStrategyData3.strategyTotalLoss, 0);

        assertEq(vault.debtRatio(), 5000 + 100 + 4786);
    }

    /*==================VAULT CONFIGURATION TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///               TEST setWithdrawalQueue() NEGATIVES        ///
    ////////////////////////////////////////////////////////////////
    function testMaxApyVaultV2__SetWithdrawalQueueNegatives() public {
        /// *************** 🔹 Setup 🔹 *************** ///

        /// Added initially
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC);
        MockStrategy mockStrategy2 = new MockStrategy(address(vault), USDC);

        MockStrategy mockStrategy3 = new MockStrategy(address(vault), USDC);

        vault.addStrategy(address(mockStrategy), 2000, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy2), 2000, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy3), 2000, type(uint72).max, 0, 200);

        /// Not added initially
        MockStrategy mockStrategy4 = new MockStrategy(address(vault), USDC);

        /// *************** 🔸 Tests 🔸 *************** ///
        /// Test adding more strategies after empty strategy
        address[20] memory queue;
        queue[0] = address(mockStrategy);
        queue[1] = address(0);
        queue[2] = address(mockStrategy2);

        vm.expectRevert(abi.encodeWithSignature("InvalidQueueOrder()"));
        vault.setWithdrawalQueue(queue);

        queue[0] = address(0);
        queue[1] = address(mockStrategy);

        vm.expectRevert(abi.encodeWithSignature("InvalidQueueOrder()"));
        vault.setWithdrawalQueue(queue);

        /// Test adding inactive strategy
        queue[0] = address(mockStrategy);
        queue[1] = address(mockStrategy2);
        queue[2] = address(mockStrategy3);
        queue[3] = address(mockStrategy4);

        vm.expectRevert(abi.encodeWithSignature("StrategyNotActive()"));
        vault.setWithdrawalQueue(queue);

        queue[0] = address(mockStrategy4);
        queue[1] = address(0);
        queue[2] = address(0);
        queue[3] = address(0);

        vm.expectRevert(abi.encodeWithSignature("StrategyNotActive()"));
        vault.setWithdrawalQueue(queue);
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST setWithdrawalQueue() POSITIVES        ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__SetWithdrawalQueuePositives() public {
        /// *************** 🔹 Setup 🔹 *************** ///

        /// Added initially
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC);
        MockStrategy mockStrategy2 = new MockStrategy(address(vault), USDC);

        MockStrategy mockStrategy3 = new MockStrategy(address(vault), USDC);

        vault.addStrategy(address(mockStrategy), 2000, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy2), 2000, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy3), 2000, type(uint72).max, 0, 200);

        /// Not added initially
        MockStrategy mockStrategy4 = new MockStrategy(address(vault), USDC);

        assertEq(vault.withdrawalQueue(0), address(mockStrategy));
        assertEq(vault.withdrawalQueue(1), address(mockStrategy2));
        assertEq(vault.withdrawalQueue(2), address(mockStrategy3));

        /// *************** 🔸 Tests 🔸 *************** ///
        /// Initial test reordering 3 strategies
        address[20] memory queue;
        queue[0] = address(mockStrategy3);
        queue[1] = address(mockStrategy);
        queue[2] = address(mockStrategy2);

        vm.expectEmit();
        emit WithdrawalQueueUpdated(queue);
        vault.setWithdrawalQueue(queue);

        uint256 maxStrategies = vault.MAXIMUM_STRATEGIES();
        for (uint256 i; i < maxStrategies;) {
            address strategy;
            if (i == 0) strategy = address(mockStrategy3);
            if (i == 1) strategy = address(mockStrategy);
            if (i == 2) strategy = address(mockStrategy2);

            assertEq(vault.withdrawalQueue(i), strategy);

            unchecked {
                ++i;
            }
        }

        /// Add strategy 4
        vault.addStrategy(address(mockStrategy4), 2000, type(uint72).max, 0, 200);
        assertEq(vault.withdrawalQueue(0), address(mockStrategy3));
        assertEq(vault.withdrawalQueue(1), address(mockStrategy));
        assertEq(vault.withdrawalQueue(2), address(mockStrategy2));
        assertEq(vault.withdrawalQueue(3), address(mockStrategy4));

        /// Reorder queue again
        queue[0] = address(mockStrategy4);
        queue[1] = address(mockStrategy2);
        queue[2] = address(mockStrategy);
        queue[3] = address(mockStrategy3);

        vm.expectEmit();
        emit WithdrawalQueueUpdated(queue);
        vault.setWithdrawalQueue(queue);

        for (uint256 i; i < maxStrategies;) {
            address strategy;
            if (i == 0) strategy = address(mockStrategy4);
            if (i == 1) strategy = address(mockStrategy2);
            if (i == 2) strategy = address(mockStrategy);
            if (i == 3) strategy = address(mockStrategy3);
            assertEq(vault.withdrawalQueue(i), strategy);

            unchecked {
                ++i;
            }
        }

        /// Reorder queue, removing one of the active strategies
        queue[0] = address(mockStrategy4);
        queue[1] = address(mockStrategy2);
        queue[2] = address(mockStrategy3);
        queue[3] = address(0);
        vm.expectEmit();
        emit WithdrawalQueueUpdated(queue);
        vault.setWithdrawalQueue(queue);

        for (uint256 i; i < maxStrategies;) {
            address strategy;
            if (i == 0) strategy = address(mockStrategy4);
            if (i == 1) strategy = address(mockStrategy2);
            if (i == 2) strategy = address(mockStrategy3);
            assertEq(vault.withdrawalQueue(i), strategy);

            unchecked {
                ++i;
            }
        }
    }

    ////////////////////////////////////////////////////////////////
    ///               TEST setEmergencyShutdown()                ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__SetEmergencyShutdown() public {
        /// Vault is NOT in emergency shutdown mode by default
        assertEq(vault.emergencyShutdown(), false);
        /// Enable emergency shutdown mode
        vm.expectEmit();
        emit EmergencyShutdownUpdated(true);
        vault.setEmergencyShutdown(true);
        assertEq(vault.emergencyShutdown(), true);
        /// Disable emergency shutdown mode
        vm.expectEmit();
        emit EmergencyShutdownUpdated(false);
        vault.setEmergencyShutdown(false);
        assertEq(vault.emergencyShutdown(), false);
    }

    ////////////////////////////////////////////////////////////////
    ///                 TEST setPerformanceFee()                 ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__SetPerformanceFee() public {
        /// Test access control
        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setPerformanceFee(5001);
        vm.stopPrank();

        vm.startPrank(users.alice);

        /// Test invalid performance fees
        vm.expectRevert(abi.encodeWithSignature("InvalidPerformanceFee()"));
        vault.setPerformanceFee(5001);

        vm.expectRevert(abi.encodeWithSignature("InvalidPerformanceFee()"));
        vault.setPerformanceFee(10_000);

        /// Test correct behavior
        vm.expectEmit();
        emit PerformanceFeeUpdated(4999);
        vault.setPerformanceFee(4999);
        assertEq(vault.performanceFee(), 4999);

        vm.expectEmit();
        emit PerformanceFeeUpdated(20);
        vault.setPerformanceFee(20);
        assertEq(vault.performanceFee(), 20);

        vm.expectEmit();
        emit PerformanceFeeUpdated(0);
        vault.setPerformanceFee(0);
        assertEq(vault.performanceFee(), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                 TEST setManagementFee()                  ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__SetManagementFee() public {
        /// Test access control
        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setManagementFee(10_001);
        vm.stopPrank();

        vm.startPrank(users.alice);

        /// Test invalid management fees
        vm.expectRevert(abi.encodeWithSignature("InvalidManagementFee()"));
        vault.setManagementFee(10_001);

        vm.expectRevert(abi.encodeWithSignature("InvalidManagementFee()"));
        vault.setManagementFee(11_882);

        /// Test correct behavior
        vm.expectEmit();
        emit ManagementFeeUpdated(9999);
        vault.setManagementFee(9999);
        assertEq(vault.managementFee(), 9999);

        vm.expectEmit();
        emit ManagementFeeUpdated(10_000);
        vault.setManagementFee(10_000);
        assertEq(vault.managementFee(), 10_000);

        vm.expectEmit();
        emit ManagementFeeUpdated(1);
        vault.setManagementFee(1);
        assertEq(vault.managementFee(), 1);

        vm.expectEmit();
        emit ManagementFeeUpdated(0);
        vault.setManagementFee(0);
        assertEq(vault.managementFee(), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                 TEST setLockedProfitDegradation()        ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__SetLockedProfitDegradation() public {
        uint256 DEGRADATION_COEFFICIENT = vault.DEGRADATION_COEFFICIENT();
        /// Test access control
        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setLockedProfitDegradation(DEGRADATION_COEFFICIENT + 1);
        vm.stopPrank();

        vm.startPrank(users.alice);

        /// Test invalid locked profit degradation
        vm.expectRevert(abi.encodeWithSignature("InvalidLockedProfitDegradation()"));
        vault.setLockedProfitDegradation(DEGRADATION_COEFFICIENT + 1);

        vm.expectRevert(abi.encodeWithSignature("InvalidLockedProfitDegradation()"));
        vault.setLockedProfitDegradation(DEGRADATION_COEFFICIENT + 2000);

        /// Test correct behavior
        vm.expectEmit();
        emit LockedProfitDegradationUpdated(9999);
        vault.setLockedProfitDegradation(9999);
        assertEq(vault.lockedProfitDegradation(), 9999);

        vm.expectEmit();
        emit LockedProfitDegradationUpdated(0);
        vault.setLockedProfitDegradation(0);
        assertEq(vault.lockedProfitDegradation(), 0);

        vm.expectEmit();
        emit LockedProfitDegradationUpdated(DEGRADATION_COEFFICIENT);
        vault.setLockedProfitDegradation(DEGRADATION_COEFFICIENT);
        assertEq(vault.lockedProfitDegradation(), DEGRADATION_COEFFICIENT);

        vm.expectEmit();
        emit LockedProfitDegradationUpdated(1e16);
        vault.setLockedProfitDegradation(1e16);
        assertEq(vault.lockedProfitDegradation(), 1e16);
    }

    ////////////////////////////////////////////////////////////////
    ///                 TEST setMaxDeposit()                   ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__SetMaxDeposit() public {
        /// Test access control
        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setDepositLimit(9999);
        vm.stopPrank();

        vm.startPrank(users.alice);

        /// Test correct behavior
        vm.expectEmit();
        emit DepositLimitUpdated(9999);
        vault.setDepositLimit(9999);
        assertEq(vault.maxDeposit(address(0)), 9999);

        vm.expectEmit();
        emit DepositLimitUpdated(0);
        vault.setDepositLimit(0);
        assertEq(vault.maxDeposit(address(0)), 0);

        vm.expectEmit();
        emit DepositLimitUpdated(type(uint256).max);
        vault.setDepositLimit(type(uint256).max);
        assertEq(vault.maxDeposit(address(0)), type(uint256).max);
    }

    ////////////////////////////////////////////////////////////////
    ///                   TEST setTreasury()                     ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__SetTreasury() public {
        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setTreasury(makeAddr("random"));

        vm.stopPrank();
        vm.startPrank(users.alice);
        vault.setTreasury(makeAddr("random"));

        assertEq(vault.treasury(), makeAddr("random"));
    }

    /*==================USER-FACING FUNCTIONS TESTS==================*/

    ////////////////////////////////////////////////////////////////
    ///                 TEST deposit() NEGATIVES                 ///
    ////////////////////////////////////////////////////////////////
    // TODO: max TVL limit or deposit limit?
    function testMaxApyVaultV2__DepositNegatives() public {
        /// *************** 🔹 Setup 🔹 *************** ///

        /// Create reentrant attacker contract
        ReentrantERC777AttackerDeposit reentrantAttacker = new ReentrantERC777AttackerDeposit();

        /// Create ERC777 token
        MockERC777 token = new MockERC777("Test", "TST", new address[](0), address(reentrantAttacker));

        MaxApyVaultV2 maxApyVault = new MaxApyVaultV2(
            /// Deploy new instance to add debt ratio and test addition
            address(token),
            "MaxApyERC777Vault",
            "max777",
            TREASURY
        );

        IMaxApyVaultV2 vaultReentrant = IMaxApyVaultV2(address(maxApyVault));

        /// Set proxy in attacker
        reentrantAttacker.setVault(vaultReentrant);

        /// Approve proxy to transfer attacker tokens
        vm.startPrank(address(reentrantAttacker));
        token.approve(address(vaultReentrant), type(uint256).max);

        vm.startPrank(users.alice);

        /// *************** 🔸 Tests 🔸 *************** ///

        /// Test vault in emergency shutdown
        vault.setEmergencyShutdown(true);
        vm.expectRevert(abi.encodeWithSignature("VaultInEmergencyShutdownMode()"));
        vault.deposit(1 * _1_USDC, users.alice);

        vault.setEmergencyShutdown(false);

        /// Test reentrancy
        vm.expectRevert(abi.encodeWithSignature("TransferFromFailed()")); // reentrancy guard
        reentrantAttacker.attack(1);

        /// Test recipient is zero address
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAddress()"));
        vault.deposit(1 * _1_USDC, address(0));

        /// Test depositing zero amount
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAmount()"));
        vault.deposit(0, users.alice);

        /// Test deposit limit exceeded
        vault.setDepositLimit(10 * _1_USDC);

        vm.expectRevert(abi.encodeWithSignature("VaultDepositLimitExceeded()"));
        vault.deposit(10 * _1_USDC + 1, users.alice);

        vault.deposit(5 * _1_USDC, users.alice);

        vm.expectRevert(abi.encodeWithSignature("VaultDepositLimitExceeded()"));
        vault.deposit(5 * _1_USDC + 1, users.alice);
    }

    ////////////////////////////////////////////////////////////////
    ///                 TEST deposit() POSITIVES                 ///
    ////////////////////////////////////////////////////////////////
    function testMaxApyVaultV2__DepositPositives() public {
        /// Deposit 1 * _1_USDC
        uint256 expectedShares = _calculateExpectedShares(1 * _1_USDC);
        vm.expectEmit();
        emit Deposit(users.alice, users.alice, 1 * _1_USDC, expectedShares);
        vault.deposit(1 * _1_USDC, users.alice);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 1 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), 1 * _1_USDC * 10 ** 6);

        /// 1 second passes
        vm.warp(block.timestamp + 1);

        /// Deposit 150
        expectedShares = _calculateExpectedShares(150 * _1_USDC);
        vm.expectEmit();
        emit Deposit(users.alice, users.alice, 150 * _1_USDC, expectedShares);
        vault.deposit(150 * _1_USDC, users.alice);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 151 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), 151 * _1_USDC * 10 ** 6);

        /// 10 days pass
        vm.warp(block.timestamp + 10 days);

        /// Deposit 10
        expectedShares = _calculateExpectedShares(10 * _1_USDC);
        vm.expectEmit();
        emit Deposit(users.alice, users.alice, 10 * _1_USDC, expectedShares);
        vault.deposit(10 * _1_USDC, users.alice);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 161 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), 151 * _1_USDC * 10 ** 6 + expectedShares);
    }

    ////////////////////////////////////////////////////////////////
    ///                 TEST redeem() NEGATIVES                ///
    ////////////////////////////////////////////////////////////////
    function testMaxApyVaultV2__RedeemNegatives() public {
        /// *************** 🔹 Setup 🔹 *************** ///

        /// Create reentrant attacker contract
        ReentrantERC777AttackerWithdraw reentrantAttacker = new ReentrantERC777AttackerWithdraw();

        /// Create ERC777 token
        MockERC777 token = new MockERC777("Test", "TST", new address[](0), address(reentrantAttacker));

        MaxApyVaultV2 maxApyVault = new MaxApyVaultV2(
            /// Deploy new instance to add debt ratio and test addition
            address(token),
            "MaxApyERC777Vault",
            "max777",
            TREASURY
        );

        IMaxApyVaultV2 vaultReentrant = IMaxApyVaultV2(address(maxApyVault));

        /// Set proxy in attacker
        reentrantAttacker.setVault(vaultReentrant);

        /// Approve proxy to transfer attacker tokens
        vm.startPrank(address(reentrantAttacker));
        token.approve(address(vaultReentrant), type(uint256).max);

        vm.startPrank(users.alice);

        /// Deposit 10 ETH in regular vault
        uint256 expectedShares = _calculateExpectedShares(10 * _1_USDC);
        vault.deposit(10 * _1_USDC, users.alice);

        /// Deposit 1 ETH in reentrant vault
        token.mint(users.alice, 1 * _1_USDC);
        token.approve(address(vaultReentrant), type(uint256).max);
        vm.expectRevert(abi.encodeWithSignature("TransferFromFailed()"));
        vaultReentrant.deposit(1 * _1_USDC, users.alice);

        /// Create lossy strategies
        MockLossyUSDCStrategy lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy2 = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy3 = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));

        /// Fund lossy strategies with USDC
        deal({token: USDC, to: address(lossyStrategy), give: 10 * _1_USDC});
        deal({token: USDC, to: address(lossyStrategy2), give: 10 * _1_USDC});
        deal({token: USDC, to: address(lossyStrategy3), give: 10 * _1_USDC});

        /// Add mock lossy strategy returning always 1 ETH loss
        vault.addStrategy(address(lossyStrategy), 1000, type(uint72).max, 0, 1000);

        /// Initially report from lossy strategy so that they have a positive `strategyTotalDebt`
        lossyStrategy.mockReport(0, 0, 0);

        StrategyData memory lossyStrategyData = vault.strategies(address(lossyStrategy));

        /// Expect 0 loss after reporting
        assertEq(lossyStrategyData.strategyTotalLoss, 0);

        /// Expect 1 * _1_USDC lent from vault to each strategy after reporting
        assertEq(lossyStrategyData.strategyTotalDebt, 1 * _1_USDC);

        /// Expect vault to hold 9 * _1_USDC (previously balance was 10 * _1_USDC, 1 * _1_USDC was transferred to strategy
        /// in the previous report)
        assertEq(IERC20(USDC).balanceOf(address(vault)), 9 * _1_USDC);

        /// *************** 🔸 Tests 🔸 *************** ///

        /// Test non reentrant
        vm.expectRevert(abi.encodeWithSignature("RedeemMoreThanMax()"));
        vaultReentrant.redeem(expectedShares, users.alice, users.alice);

        /// Test 0 shares
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroShares()"));
        vault.redeem(0, users.alice, users.alice);

        /// Expect revert due to max loss reached

        /// 9.99% max loss allowed

        /// 📝 MAX LOSS REVERTS EXPLANATION
        // * Vault initially had 10 * _1_USDC which were deposited by alice
        // * After initally reporting, the vault transferred 1 * _1_USDC to the strategy (strategy was configured with
        // 10% debt ratio)

        // * To withdraw 10 * _1_USDC: vault does not have enough funds, the strategy will be unwinded to cover requested amount

        // ⬇️ Expected withdrawal flow ⬇️
        // * `valueToWithdraw` -> 10 * _1_USDC
        // * `vaultBalance` -> 9 * _1_USDC (1 * _1_USDC was transferred to strategy in previous report)
        // * `amountNeeded` -> 1 * _1_USDC
        // ---- Strategy reports 1 * _1_USDC loss ----
        // * `totalLoss` -> 1 * _1_USDC
        // * `valueToWithdraw` after loss -> 9 * _1_USDC (user incurrs the 1 * _1_USDC loss)
        // * Losing of 1 * _1_USDC from a 10 * _1_USDC requested withdrawal represents a 10% loss. Setting the max
        //   loss at any number below 10% should revert with `MaxLossReached()`
    }

    ////////////////////////////////////////////////////////////////
    ///                 TEST redeem() POSITIVES                ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__RedeemPositives() public {
        /// *************** 🔸 Tests 🔸 *************** ///

        /// ⭕️ SCENARIO 1: Deposit 10 USDC, withdraw 10 USDC from vault.
        /// - No strategies involved
        /// Goal: test adding and removing liquidity without needing to withdraw from strategies

        uint256 snapshotId = vm.snapshot();
        /// Deposit 10 USDC in vault
        {
            uint256 shares = _deposit(users.alice, vault, 10 * _1_USDC);

            uint256 redeemed = _redeem(users.alice, vault, shares, 0);
            assertEq(redeemed, 10 * _1_USDC);
        }
        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 2: Deposit 500 USDC, initially withdraw 10 USDC from vault, then withdraw 400 USDC, finally withdraw the remaining 90 USDC
        /// - No strategies involved
        /// Goal: test  adding and removing liquidity in different steps, without needing to withdraw from strategies

        /// Deposit 500 USDC in vault
        _deposit(users.alice, vault, 500 * _1_USDC);

        uint256 aliceBalanceBefore = IERC20(USDC).balanceOf(address(users.alice));

        /// Withdraw 10 USDC
        uint256 valueWithdrawn = _redeem(users.alice, vault, 10 * 10 ** vault.decimals(), 0);

        /// Withdraw 400 USDC
        valueWithdrawn += _redeem(users.alice, vault, 400 * 10 ** vault.decimals(), 0);

        /// Withdraw 90 USDC
        valueWithdrawn += _redeem(users.alice, vault, 90 * 10 ** vault.decimals(), 0);

        assertEq(IERC20(USDC).balanceOf(address(vault)), 0);
        assertEq(IERC20(USDC).balanceOf(address(users.alice)), aliceBalanceBefore + valueWithdrawn);
        assertEq(valueWithdrawn, 500 * _1_USDC);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        /// ⭕️ SCENARIO 3: Deposit 20 USDC, transfer 50% to strategy and finally withdraw back
        /// - User deposits 20 USDC
        /// - Lossy strategy is added with 50% debt ratio
        /// - Strategy reports and 50% of vault funds, or 10 USDC (0.5 * 20 USDC), gets transferred to strategy
        /// - User tries to withdraw back 20 USDC, 10 USDC get withdrawn from strategy with 1 USDC loss
        /// - User finally gets 19 USDC due to strategy losing 1 USDC
        /// Goal: test adding and removing liquidity withdrawing from  a single strategy
        ///     - assert computing the `amountNeeded` properly
        ///     - assert ` Math.min(amountNeeded,strategies[strategy].strategyTotalDebt);`, where `amountNeeded` >= `strategyTotalDebt`
        ///     - assert a `withdrawn` amount from strategy > 0
        ///     - assert reporting loss due to `loss` being != 0 for both vault and strategy
        ///     - assert changing in ratios and debts
        ///     - assert reducing vault's `totalDebt`
        ///     - assert emitting `WithdrawFromStrategy`

        /// Deposit 20 USDC in vault
        uint256 shares = _deposit(users.alice, vault, 20 * _1_USDC);

        vm.startPrank(users.alice);
        MockLossyUSDCStrategy lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));

        /// Add mock lossy strategy returning always 1 ETH loss
        vault.addStrategy(
            address(lossyStrategy),
            5000,
            /// 50% debt ratio
            type(uint72).max,
            0,
            1000
        );

        /// Initially report from lossy strategy so that they have a positive `strategyTotalDebt`
        lossyStrategy.mockReport(0, 0, 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy)), 10 * _1_USDC);
        lossyStrategy.setEstimatedTotalAssets(10 * _1_USDC);

        aliceBalanceBefore = IERC20(USDC).balanceOf(users.alice);
        StrategyWithdrawalPreviousData memory previousStrategyData;

        previousStrategyData.balance = IERC20(USDC).balanceOf(address(lossyStrategy));

        /// Store previous data
        uint256 vaultPreviousDebtRatio = vault.debtRatio();

        previousStrategyData.debtRatio = vault.strategies(address(lossyStrategy)).strategyDebtRatio;
        previousStrategyData.totalLoss = vault.strategies(address(lossyStrategy)).strategyTotalLoss;
        previousStrategyData.totalDebt = vault.strategies(address(lossyStrategy)).strategyTotalDebt;

        uint256 expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategy), 1 * _1_USDC);

        // we can only withdraw 19 USDC since the lossy strategy lost 1 USDC
        valueWithdrawn = _redeem(users.alice, vault, shares, _1_USDC);

        /// Assert balances
        assertEq(valueWithdrawn, 19 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(users.alice), aliceBalanceBefore + 19 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy)), previousStrategyData.balance - 9 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 0);

        /// Assert parameters
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyDebtRatio,
            previousStrategyData.debtRatio - expectedRatioChange
        );
        assertEq(vault.debtRatio(), vaultPreviousDebtRatio - expectedRatioChange);
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalLoss, previousStrategyData.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalDebt, previousStrategyData.totalDebt - 10 * _1_USDC
        );
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.totalIdle(), 0);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        /// ⭕️ SCENARIO 4: Deposit 50 USDC, add two strategies, transfer 50% to SECOND strategy and leave first strategy empty
        /// - User deposits 50 USDC
        /// - Add first strategy with 0% debt ratio
        /// - Add second strategy with 50% debt ratio
        /// - Strategy funded reports and 50% of vault funds, or 25 USDC (0.5 * 50 USDC), gets transferred to funded strategy
        /// - User tries to withdraw back 50 USDC, first strategy gets skipped, 25 USDC get withdrawn from second strategy with 1 USDC loss
        /// - User finally gets 49 USDC due to strategy losing 1 USDC
        /// Goal: test adding and removing liquidity, where first strategy does not have funds but second does
        ///     - assert `type(uint256).max` gets user share balance
        ///     - assert `continue` gets executed if the current strategy has no debt to be withdrawn

        /// Deposit 50 USDC in vault
        _deposit(users.alice, vault, 50 * _1_USDC);

        vm.startPrank(users.alice);

        lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));

        MockLossyUSDCStrategy lossyStrategyFunded =
            new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));

        vault.addStrategy(
            address(lossyStrategy),
            0,
            /// 0% debt ratio
            type(uint72).max,
            0,
            1000
        );

        vault.addStrategy(
            address(lossyStrategyFunded),
            5000,
            /// 50% debt ratio
            type(uint72).max,
            0,
            1000
        );

        /// Initially report from lossy strategy funded so that they have a positive `strategyTotalDebt`
        lossyStrategyFunded.mockReport(0, 0, 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategyFunded)), 25 * _1_USDC);
        lossyStrategyFunded.setEstimatedTotalAssets(25 * _1_USDC);

        /// Compute previous values
        aliceBalanceBefore = IERC20(USDC).balanceOf(users.alice);

        vaultPreviousDebtRatio = vault.debtRatio();

        previousStrategyData.balance = IERC20(USDC).balanceOf(address(lossyStrategyFunded));
        previousStrategyData.debtRatio = vault.strategies(address(lossyStrategyFunded)).strategyDebtRatio;
        previousStrategyData.totalLoss = vault.strategies(address(lossyStrategyFunded)).strategyTotalLoss;
        previousStrategyData.totalDebt = vault.strategies(address(lossyStrategyFunded)).strategyTotalDebt;
        expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategyFunded), 1 * _1_USDC);

        valueWithdrawn = _redeem(users.alice, vault, 50 * 10 ** vault.decimals(), _1_USDC);

        /// Assert balances
        assertEq(valueWithdrawn, 49 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(users.alice), aliceBalanceBefore + 49 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategyFunded)), previousStrategyData.balance - 24 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 0);

        /// Assert parameters
        assertEq(
            vault.strategies(address(lossyStrategyFunded)).strategyDebtRatio,
            previousStrategyData.debtRatio - expectedRatioChange
        );
        assertEq(vault.debtRatio(), vaultPreviousDebtRatio - expectedRatioChange);
        assertEq(
            vault.strategies(address(lossyStrategyFunded)).strategyTotalLoss,
            previousStrategyData.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategyFunded)).strategyTotalDebt,
            previousStrategyData.totalDebt - 25 * _1_USDC
        );
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.totalIdle(), 0);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        /// ⭕️ SCENARIO 5: Deposit 100 USDC, add three strategies, transfer 50% to first strategy, 25% to second and 25% to third strategy
        /// - Withdraw 65 USDC
        /// - User deposits 100 USDC
        /// - Add first strategy with 50% debt ratio
        /// - Add second strategy with 25% debt ratio
        /// - Add third strategy with 25% debt ratio
        /// - All strategies report.
        ///      - 50% of vault funds, or 50 USDC (0.5 * 100 USDC), gets transferred to first strategy
        ///      - 25% of vault funds, or 25 USDC (0.25 * 100 USDC), gets transferred to second strategy
        ///      - 25% of vault funds, or 25 USDC (0.25 * 100 USDC), gets transferred to third strategy
        /// - User tries to withdraw back 65 USDC
        /// - User finally gets 63 USDC due to strategy losing 1 USDC per strategy
        /// Goal: test withdrawing from several strategies
        ///     - assert vault stops withdrawing when `vaultBalance` is greater than `valueToWithdraw`
        ///     - assert loss is reported to all strategies losing after withdrawal
        ///     - assert vault stops withdrawing when `vaultBalance` is greater than `valueToWithdraw`
        ///     - assert vault stops withdrawing when `vaultBalance` is greater than `valueToWithdraw`

        /// Deposit 100 USDC in vault
        _deposit(users.alice, vault, 100 * _1_USDC);

        vm.startPrank(users.alice);

        lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy2 = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy3 = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));

        vault.addStrategy(
            address(lossyStrategy),
            5000,
            /// 50% debt ratio
            type(uint72).max,
            0,
            1000
        );

        vault.addStrategy(
            address(lossyStrategy2),
            2500,
            /// 25% debt ratio
            type(uint72).max,
            0,
            1000
        );

        vault.addStrategy(
            address(lossyStrategy3),
            2500,
            /// 25% debt ratio
            type(uint72).max,
            0,
            1000
        );

        /// Report from lossy strategies so that they have a positive `strategyTotalDebt`
        lossyStrategy.mockReport(0, 0, 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy)), 50 * _1_USDC);
        lossyStrategy2.mockReport(0, 0, 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy2)), 25 * _1_USDC);
        lossyStrategy3.mockReport(0, 0, 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy3)), 25 * _1_USDC);

        /// Set the estimated total assets of the strategies
        lossyStrategy.setEstimatedTotalAssets(50 * _1_USDC);
        lossyStrategy2.setEstimatedTotalAssets(25 * _1_USDC);
        lossyStrategy3.setEstimatedTotalAssets(25 * _1_USDC);

        /// Compute previous values
        aliceBalanceBefore = IERC20(USDC).balanceOf(users.alice);

        vaultPreviousDebtRatio = vault.debtRatio();

        /// First strategy previous data

        previousStrategyData.balance = IERC20(USDC).balanceOf(address(lossyStrategy));
        previousStrategyData.debtRatio = vault.strategies(address(lossyStrategy)).strategyDebtRatio;
        previousStrategyData.totalLoss = vault.strategies(address(lossyStrategy)).strategyTotalLoss;
        previousStrategyData.totalDebt = vault.strategies(address(lossyStrategy)).strategyTotalDebt;

        /// Second strategy previous data
        StrategyWithdrawalPreviousData memory previousStrategy2Data;

        previousStrategy2Data.balance = IERC20(USDC).balanceOf(address(lossyStrategy2));
        previousStrategy2Data.debtRatio = vault.strategies(address(lossyStrategy2)).strategyDebtRatio;
        previousStrategy2Data.totalLoss = vault.strategies(address(lossyStrategy2)).strategyTotalLoss;
        previousStrategy2Data.totalDebt = vault.strategies(address(lossyStrategy2)).strategyTotalDebt;

        /// Third strategy previous data
        StrategyWithdrawalPreviousData memory previousStrategy3Data;

        previousStrategy3Data.balance = IERC20(USDC).balanceOf(address(lossyStrategy3));
        previousStrategy3Data.debtRatio = vault.strategies(address(lossyStrategy3)).strategyDebtRatio;
        previousStrategy3Data.totalLoss = vault.strategies(address(lossyStrategy3)).strategyTotalLoss;
        previousStrategy3Data.totalDebt = vault.strategies(address(lossyStrategy3)).strategyTotalDebt;

        expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategy), 1 * _1_USDC);

        uint256 expectedRatioChange2 = _computeExpectedRatioChange(vault, address(lossyStrategy2), 1 * _1_USDC);

        valueWithdrawn = _redeem(
            users.alice,
            vault,
            65 * 10 ** vault.decimals(),
            2 * _1_USDC // 2 USDC loss expected due to withdrawal
        );

        /// Assert balances
        {
            assertEq(valueWithdrawn, 63 * _1_USDC);
            assertEq(IERC20(USDC).balanceOf(users.alice), aliceBalanceBefore + 63 * _1_USDC);
            assertEq(vault.balanceOf(users.alice), 35 * _1_USDC * 10 ** 6);
            assertEq(IERC20(USDC).balanceOf(address(lossyStrategy)), previousStrategyData.balance - 49 * _1_USDC);
            /// withdraw 49 (50 ETH - 1 ETH loss) ETH from first strategy

            assertEq(IERC20(USDC).balanceOf(address(lossyStrategy2)), previousStrategy2Data.balance - 14 * _1_USDC);
            /// withdraw 14 (15 ETH - 1 ETH loss) ETH from second strategy

            assertEq(IERC20(USDC).balanceOf(address(lossyStrategy3)), previousStrategy3Data.balance);
            /// no loss incurred in third strategy

            assertEq(IERC20(USDC).balanceOf(address(vault)), 0);
        }
        /// Assert parameters

        /// First strategy assertions
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyDebtRatio,
            previousStrategyData.debtRatio - expectedRatioChange
        );

        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalLoss, previousStrategyData.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalDebt, previousStrategyData.totalDebt - 50 * _1_USDC
        );

        /// Second strategy assertions
        assertLt(
            vault.strategies(address(lossyStrategy2)).strategyDebtRatio,
            previousStrategy2Data.debtRatio - expectedRatioChange2
        );

        assertEq(
            vault.strategies(address(lossyStrategy2)).strategyTotalLoss, previousStrategy2Data.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategy2)).strategyTotalDebt, previousStrategy2Data.totalDebt - 15 * _1_USDC
        );

        /// Third strategy assertions
        assertEq(vault.strategies(address(lossyStrategy3)).strategyDebtRatio, previousStrategy3Data.debtRatio);

        assertEq(vault.strategies(address(lossyStrategy3)).strategyTotalLoss, 0);
        assertEq(vault.strategies(address(lossyStrategy3)).strategyTotalDebt, 25 * _1_USDC);

        /// Vault assertions
        assertLt(vault.debtRatio(), vaultPreviousDebtRatio - (expectedRatioChange + expectedRatioChange2));
        assertEq(vault.totalDebt(), 35 * _1_USDC);
        /// 100 ETH - 50 ETH - 15 ETH

        assertEq(vault.totalIdle(), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                 TEST withdraw() NEGATIVES                ///
    ////////////////////////////////////////////////////////////////
    function testMaxApyVaultV2__WithdrawNegatives() public {
        /// *************** 🔹 Setup 🔹 *************** ///

        /// Create reentrant attacker contract
        ReentrantERC777AttackerWithdraw reentrantAttacker = new ReentrantERC777AttackerWithdraw();

        /// Create ERC777 token
        MockERC777 token = new MockERC777("Test", "TST", new address[](0), address(reentrantAttacker));

        MaxApyVaultV2 maxApyVault = new MaxApyVaultV2(
            /// Deploy new instance to add debt ratio and test addition
            address(token),
            "MaxApyERC777Vault",
            "max777",
            TREASURY
        );

        IMaxApyVaultV2 vaultReentrant = IMaxApyVaultV2(address(maxApyVault));

        /// Set proxy in attacker
        reentrantAttacker.setVault(vaultReentrant);

        /// Approve proxy to transfer attacker tokens
        vm.startPrank(address(reentrantAttacker));
        token.approve(address(vaultReentrant), type(uint256).max);

        vm.startPrank(users.alice);

        /// Deposit 10 ETH in regular vault
        uint256 expectedShares = _calculateExpectedShares(10 * _1_USDC);
        vault.deposit(10 * _1_USDC, users.alice);

        /// Deposit 1 ETH in reentrant vault
        token.mint(users.alice, 1 * _1_USDC);
        token.approve(address(vaultReentrant), type(uint256).max);
        vm.expectRevert(abi.encodeWithSignature("TransferFromFailed()"));
        vaultReentrant.deposit(1 * _1_USDC, users.alice);

        /// Create lossy strategies
        MockLossyUSDCStrategy lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy2 = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy3 = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));

        /// Fund lossy strategies with USDC
        deal({token: USDC, to: address(lossyStrategy), give: 10 * _1_USDC});
        deal({token: USDC, to: address(lossyStrategy2), give: 10 * _1_USDC});
        deal({token: USDC, to: address(lossyStrategy3), give: 10 * _1_USDC});

        /// Add mock lossy strategy returning always 1 ETH loss
        vault.addStrategy(address(lossyStrategy), 1000, type(uint72).max, 0, 1000);

        /// Initially report from lossy strategy so that they have a positive `strategyTotalDebt`
        lossyStrategy.mockReport(0, 0, 0);

        StrategyData memory lossyStrategyData = vault.strategies(address(lossyStrategy));

        /// Expect 0 loss after reporting
        assertEq(lossyStrategyData.strategyTotalLoss, 0);

        /// Expect 1 * _1_USDC lent from vault to each strategy after reporting
        assertEq(lossyStrategyData.strategyTotalDebt, 1 * _1_USDC);

        /// Expect vault to hold 9 * _1_USDC (previously balance was 10 * _1_USDC, 1 * _1_USDC was transferred to strategy
        /// in the previous report)
        assertEq(IERC20(USDC).balanceOf(address(vault)), 9 * _1_USDC);

        /// *************** 🔸 Tests 🔸 *************** ///

        /// Test non reentrant
        vm.expectRevert(abi.encodeWithSignature("WithdrawMoreThanMax()"));
        vaultReentrant.withdraw(10 * _1_USDC, users.alice, users.alice);

        /// Test 0 assets
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAmount()"));
        vault.withdraw(0, users.alice, users.alice);

        /// Expect revert due to max loss reached

        /// 9.99% max loss allowed

        /// 📝 MAX LOSS REVERTS EXPLANATION
        // * Vault initially had 10 * _1_USDC which were deposited by alice
        // * After initally reporting, the vault transferred 1 * _1_USDC to the strategy (strategy was configured with
        // 10% debt ratio)

        // * To withdraw 10 * _1_USDC: vault does not have enough funds, the strategy will be unwinded to cover requested amount

        // ⬇️ Expected withdrawal flow ⬇️
        // * `valueToWithdraw` -> 10 * _1_USDC
        // * `vaultBalance` -> 9 * _1_USDC (1 * _1_USDC was transferred to strategy in previous report)
        // * `amountNeeded` -> 1 * _1_USDC
        // ---- Strategy reports 1 * _1_USDC loss ----
        // * `totalLoss` -> 1 * _1_USDC
        // * `valueToWithdraw` after loss -> 9 * _1_USDC (user incurrs the 1 * _1_USDC loss)
        // * Losing of 1 * _1_USDC from a 10 * _1_USDC requested withdrawal represents a 10% loss. Setting the max
        //   loss at any number below 10% should revert with `MaxLossReached()`
    }

    ////////////////////////////////////////////////////////////////
    ///                 TEST withdraw() POSITIVES                ///
    ////////////////////////////////////////////////////////////////

    function testMaxApyVaultV2__WithdrawPositives() public {
        /// *************** 🔸 Tests 🔸 *************** ///

        /// ⭕️ SCENARIO 1: Deposit 10 USDC, withdraw 10 USDC from vault.
        /// - No strategies involved
        /// Goal: test adding and removing liquidity without needing to withdraw from strategies

        uint256 snapshotId = vm.snapshot();
        /// Deposit 10 USDC in vault
        {
            _deposit(users.alice, vault, 10 * _1_USDC);

            uint256 withdrawn = _withdraw(users.alice, vault, 10 * _1_USDC);
            assertEq(withdrawn, 10 * _1_USDC);
        }
        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 2: Deposit 500 USDC, initially withdraw 10 USDC from vault, then withdraw 400 USDC, finally withdraw the remaining 90 USDC
        /// - No strategies involved
        /// Goal: test  adding and removing liquidity in different steps, without needing to withdraw from strategies

        /// Deposit 500 USDC in vault
        _deposit(users.alice, vault, 500 * _1_USDC);

        uint256 aliceBalanceBefore = IERC20(USDC).balanceOf(address(users.alice));

        /// Withdraw 10 USDC
        uint256 valueWithdrawn = _withdraw(users.alice, vault, 10 * _1_USDC);

        /// Withdraw 400 USDC
        valueWithdrawn += _withdraw(users.alice, vault, 400 * _1_USDC);

        /// Withdraw 90 USDC
        valueWithdrawn += _withdraw(users.alice, vault, 90 * _1_USDC);

        assertEq(IERC20(USDC).balanceOf(address(vault)), 0);
        assertEq(IERC20(USDC).balanceOf(address(users.alice)), aliceBalanceBefore + valueWithdrawn);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        /// ⭕️ SCENARIO 3: Deposit 20 USDC, transfer 50% to strategy and finally withdraw back
        /// - User deposits 20 USDC
        /// - Lossy strategy is added with 50% debt ratio
        /// - Strategy reports and 50% of vault funds, or 10 USDC (0.5 * 20 USDC), gets transferred to strategy
        /// - User tries to withdraw back 20 USDC, 19 USDC get withdrawn from strategy with 1 USDC loss
        /// - User finally gets 19 USDC due to strategy losing 1 USDC
        /// Goal: test adding and removing liquidity withdrawing from  a single strategy
        ///     - assert computing the `amountNeeded` properly
        ///     - assert ` Math.min(amountNeeded,strategies[strategy].strategyTotalDebt);`, where `amountNeeded` >= `strategyTotalDebt`
        ///     - assert a `withdrawn` amount from strategy > 0
        ///     - assert reporting loss due to `loss` being != 0 for both vault and strategy
        ///     - assert changing in ratios and debts
        ///     - assert reducing vault's `totalDebt`
        ///     - assert emitting `WithdrawFromStrategy`

        /// Deposit 20 USDC in vault
        _deposit(users.alice, vault, 20 * _1_USDC);

        vm.startPrank(users.alice);
        MockLossyUSDCStrategy lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));

        /// Add mock lossy strategy returning always 1 ETH loss
        vault.addStrategy(
            address(lossyStrategy),
            5000,
            /// 50% debt ratio
            type(uint72).max,
            0,
            1000
        );

        /// Initially report from lossy strategy so that they have a positive `strategyTotalDebt`
        lossyStrategy.mockReport(0, 0, 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy)), 10 * _1_USDC);
        lossyStrategy.setEstimatedTotalAssets(10 * _1_USDC);

        aliceBalanceBefore = IERC20(USDC).balanceOf(users.alice);
        StrategyWithdrawalPreviousData memory previousStrategyData;

        previousStrategyData.balance = IERC20(USDC).balanceOf(address(lossyStrategy));

        /// Store previous data
        uint256 vaultPreviousDebtRatio = vault.debtRatio();

        previousStrategyData.debtRatio = vault.strategies(address(lossyStrategy)).strategyDebtRatio;
        previousStrategyData.totalLoss = vault.strategies(address(lossyStrategy)).strategyTotalLoss;
        previousStrategyData.totalDebt = vault.strategies(address(lossyStrategy)).strategyTotalDebt;

        uint256 expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategy), 1 * _1_USDC);

        // we can only withdraw 19 USDC since the lossy strategy lost 1 USDC
        valueWithdrawn = _withdraw(users.alice, vault, 19 * _1_USDC);

        /// Assert balances
        assertEq(valueWithdrawn, 19 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(users.alice), aliceBalanceBefore + 19 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy)), previousStrategyData.balance - 9 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 0);

        /// Assert parameters
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyDebtRatio,
            previousStrategyData.debtRatio - expectedRatioChange
        );
        assertEq(vault.debtRatio(), vaultPreviousDebtRatio - expectedRatioChange);
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalLoss, previousStrategyData.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalDebt, previousStrategyData.totalDebt - 10 * _1_USDC
        );
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.totalIdle(), 0);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        /// ⭕️ SCENARIO 4: Deposit 50 USDC, add two strategies, transfer 50% to SECOND strategy and leave first strategy empty
        /// - User deposits 50 USDC
        /// - Add first strategy with 0% debt ratio
        /// - Add second strategy with 50% debt ratio
        /// - Strategy funded reports and 50% of vault funds, or 25 USDC (0.5 * 50 USDC), gets transferred to funded strategy
        /// - User tries to withdraw back 50 USDC, first strategy gets skipped, 25 USDC get withdrawn from second strategy with 1 USDC loss
        /// - User finally gets 49 USDC due to strategy losing 1 USDC
        /// Goal: test adding and removing liquidity, where first strategy does not have funds but second does
        ///     - assert `type(uint256).max` gets user share balance
        ///     - assert `continue` gets executed if the current strategy has no debt to be withdrawn

        /// Deposit 50 USDC in vault
        _deposit(users.alice, vault, 50 * _1_USDC);

        vm.startPrank(users.alice);

        lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));

        MockLossyUSDCStrategy lossyStrategyFunded =
            new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));

        vault.addStrategy(
            address(lossyStrategy),
            0,
            /// 0% debt ratio
            type(uint72).max,
            0,
            1000
        );

        vault.addStrategy(
            address(lossyStrategyFunded),
            5000,
            /// 50% debt ratio
            type(uint72).max,
            0,
            1000
        );

        /// Initially report from lossy strategy funded so that they have a positive `strategyTotalDebt`
        lossyStrategyFunded.mockReport(0, 0, 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategyFunded)), 25 * _1_USDC);
        lossyStrategyFunded.setEstimatedTotalAssets(25 * _1_USDC);

        /// Compute previous values
        aliceBalanceBefore = IERC20(USDC).balanceOf(users.alice);

        vaultPreviousDebtRatio = vault.debtRatio();

        previousStrategyData.balance = IERC20(USDC).balanceOf(address(lossyStrategyFunded));
        previousStrategyData.debtRatio = vault.strategies(address(lossyStrategyFunded)).strategyDebtRatio;
        previousStrategyData.totalLoss = vault.strategies(address(lossyStrategyFunded)).strategyTotalLoss;
        previousStrategyData.totalDebt = vault.strategies(address(lossyStrategyFunded)).strategyTotalDebt;
        expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategyFunded), 1 * _1_USDC);

        valueWithdrawn = _withdraw(users.alice, vault, 50 * _1_USDC - _1_USDC);

        /// Assert balances
        assertEq(valueWithdrawn, 49 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(users.alice), aliceBalanceBefore + 49 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategyFunded)), previousStrategyData.balance - 24 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(vault)), 0);

        /// Assert parameters
        assertEq(
            vault.strategies(address(lossyStrategyFunded)).strategyDebtRatio,
            previousStrategyData.debtRatio - expectedRatioChange
        );
        assertEq(vault.debtRatio(), vaultPreviousDebtRatio - expectedRatioChange);
        assertEq(
            vault.strategies(address(lossyStrategyFunded)).strategyTotalLoss,
            previousStrategyData.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategyFunded)).strategyTotalDebt,
            previousStrategyData.totalDebt - 25 * _1_USDC
        );
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.totalIdle(), 0);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        /// ⭕️ SCENARIO 5: Deposit 100 USDC, add three strategies, transfer 50% to first strategy, 25% to second and 25% to third strategy
        /// - Withdraw 65 USDC
        /// - User deposits 100 USDC
        /// - Add first strategy with 50% debt ratio
        /// - Add second strategy with 25% debt ratio
        /// - Add third strategy with 25% debt ratio
        /// - All strategies report.
        ///      - 50% of vault funds, or 50 USDC (0.5 * 100 USDC), gets transferred to first strategy
        ///      - 25% of vault funds, or 25 USDC (0.25 * 100 USDC), gets transferred to second strategy
        ///      - 25% of vault funds, or 25 USDC (0.25 * 100 USDC), gets transferred to third strategy
        /// - User tries to withdraw back 65 USDC
        /// - User finally gets 63 USDC due to strategy losing 1 USDC per strategy
        /// Goal: test withdrawing from several strategies
        ///     - assert vault stops withdrawing when `vaultBalance` is greater than `valueToWithdraw`
        ///     - assert loss is reported to all strategies losing after withdrawal
        ///     - assert vault stops withdrawing when `vaultBalance` is greater than `valueToWithdraw`
        ///     - assert vault stops withdrawing when `vaultBalance` is greater than `valueToWithdraw`

        /// Deposit 100 USDC in vault
        _deposit(users.alice, vault, 100 * _1_USDC);

        vm.startPrank(users.alice);

        lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy2 = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy3 = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));

        vault.addStrategy(
            address(lossyStrategy),
            5000,
            /// 50% debt ratio
            type(uint72).max,
            0,
            1000
        );

        vault.addStrategy(
            address(lossyStrategy2),
            2500,
            /// 25% debt ratio
            type(uint72).max,
            0,
            1000
        );

        vault.addStrategy(
            address(lossyStrategy3),
            2500,
            /// 25% debt ratio
            type(uint72).max,
            0,
            1000
        );

        /// Report from lossy strategies so that they have a positive `strategyTotalDebt`
        lossyStrategy.mockReport(0, 0, 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy)), 50 * _1_USDC);
        lossyStrategy2.mockReport(0, 0, 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy2)), 25 * _1_USDC);
        lossyStrategy3.mockReport(0, 0, 0);
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy3)), 25 * _1_USDC);

        /// Set the estimated total assets of the strategies
        lossyStrategy.setEstimatedTotalAssets(50 * _1_USDC);
        lossyStrategy2.setEstimatedTotalAssets(25 * _1_USDC);
        lossyStrategy3.setEstimatedTotalAssets(25 * _1_USDC);

        /// Compute previous values
        aliceBalanceBefore = IERC20(USDC).balanceOf(users.alice);

        vaultPreviousDebtRatio = vault.debtRatio();

        /// First strategy previous data
        previousStrategyData.balance = IERC20(USDC).balanceOf(address(lossyStrategy));
        previousStrategyData.debtRatio = vault.strategies(address(lossyStrategy)).strategyDebtRatio;
        previousStrategyData.totalLoss = vault.strategies(address(lossyStrategy)).strategyTotalLoss;
        previousStrategyData.totalDebt = vault.strategies(address(lossyStrategy)).strategyTotalDebt;

        /// Second strategy previous data
        StrategyWithdrawalPreviousData memory previousStrategy2Data;

        previousStrategy2Data.balance = IERC20(USDC).balanceOf(address(lossyStrategy2));
        previousStrategy2Data.debtRatio = vault.strategies(address(lossyStrategy2)).strategyDebtRatio;
        previousStrategy2Data.totalLoss = vault.strategies(address(lossyStrategy2)).strategyTotalLoss;
        previousStrategy2Data.totalDebt = vault.strategies(address(lossyStrategy2)).strategyTotalDebt;

        /// Third strategy previous data
        StrategyWithdrawalPreviousData memory previousStrategy3Data;

        previousStrategy3Data.balance = IERC20(USDC).balanceOf(address(lossyStrategy3));
        previousStrategy3Data.debtRatio = vault.strategies(address(lossyStrategy3)).strategyDebtRatio;
        previousStrategy3Data.totalLoss = vault.strategies(address(lossyStrategy3)).strategyTotalLoss;
        previousStrategy3Data.totalDebt = vault.strategies(address(lossyStrategy3)).strategyTotalDebt;

        expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategy), 1 * _1_USDC);

        uint256 expectedRatioChange2 = _computeExpectedRatioChange(vault, address(lossyStrategy2), 1 * _1_USDC);

        valueWithdrawn = _withdraw(
            users.alice,
            vault,
            65 * _1_USDC - 2 * _1_USDC // 2 USDC loss expected due to withdrawal
        );

        /// Assert balances
        {
            assertEq(valueWithdrawn, 63 * _1_USDC);
            assertEq(IERC20(USDC).balanceOf(users.alice), aliceBalanceBefore + 63 * _1_USDC);
            assertEq(vault.balanceOf(users.alice), 35 * _1_USDC * 10 ** 6);
            assertEq(IERC20(USDC).balanceOf(address(lossyStrategy)), previousStrategyData.balance - 49 * _1_USDC, "s1");
            /// withdraw 49 (50 ETH - 1 ETH loss) ETH from first strategy

            assertEq(
                IERC20(USDC).balanceOf(address(lossyStrategy2)), previousStrategy2Data.balance - 14 * _1_USDC, "s2"
            );
            /// withdraw 14 (15 ETH - 1 ETH loss) ETH from second strategy

            assertEq(IERC20(USDC).balanceOf(address(lossyStrategy3)), previousStrategy3Data.balance, "s3");
            /// no loss incurred in third strategy

            assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "v");
        }

        /// Assert parameters

        /// First strategy assertions
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyDebtRatio,
            previousStrategyData.debtRatio - expectedRatioChange
        );

        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalLoss, previousStrategyData.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalDebt, previousStrategyData.totalDebt - 50 * _1_USDC
        );

        /// Second strategy assertions
        assertLt(
            vault.strategies(address(lossyStrategy2)).strategyDebtRatio,
            previousStrategy2Data.debtRatio - expectedRatioChange2
        );

        assertEq(
            vault.strategies(address(lossyStrategy2)).strategyTotalLoss, previousStrategy2Data.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategy2)).strategyTotalDebt, previousStrategy2Data.totalDebt - 15 * _1_USDC
        );

        /// Third strategy assertions
        assertEq(vault.strategies(address(lossyStrategy3)).strategyDebtRatio, previousStrategy3Data.debtRatio);

        assertEq(vault.strategies(address(lossyStrategy3)).strategyTotalLoss, 0);
        assertEq(vault.strategies(address(lossyStrategy3)).strategyTotalDebt, 25 * _1_USDC);

        /// Vault assertions
        assertLt(vault.debtRatio(), vaultPreviousDebtRatio - (expectedRatioChange + expectedRatioChange2));
        assertEq(vault.totalDebt(), 35 * _1_USDC);
        /// 100 ETH - 50 ETH - 15 ETH

        assertEq(vault.totalIdle(), 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                 TEST report() NEGATIVES                  ///
    ////////////////////////////////////////////////////////////////
    function testMaxApyVaultV2__ReportNegatives() public {
        /// *************** 🔹 Setup 🔹 *************** ///
        /// Grant Alice a strategy role
        vault.grantRoles(users.alice, vault.STRATEGY_ROLE());

        MockLossyUSDCStrategy lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));

        vault.addStrategy(address(lossyStrategy), 4000, 0, 0, 0);

        lossyStrategy.mockReport(0, 0, 0);
        /// *************** 🔸 Tests 🔸 *************** ///

        /// Check access control with unauthorized user
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.report(0, 0, 0, 0);

        vm.stopPrank();

        vm.startPrank(address(lossyStrategy));

        /// Check report with a strategy who does not have enough funds to cover `gain` and `debtPayment`
        vm.expectRevert(abi.encodeWithSignature("InvalidReportedGainAndDebtPayment()"));
        vault.report(1, 1, 0, 0);
        /// `gain` (1) + `debtPayment` (0) are gt. `balanceOf(strategy)`

        vm.expectRevert(abi.encodeWithSignature("InvalidReportedGainAndDebtPayment()"));
        vault.report(0, 0, 0, 1);
        /// `gain` (0) + `debtPayment` (1) are gt. `balanceOf(strategy)`

        vm.expectRevert(abi.encodeWithSignature("InvalidReportedGainAndDebtPayment()"));
        vault.report(uint128(1 * _1_USDC), uint128(1 * _1_USDC), 0, uint128(450 * _1_USDC));
        /// `gain` (1 ETH) + `debtPayment` (450 ETH) are gt. `balanceOf(strategy)`

        /// Check reported loss is higher than strategy total debt
        vm.expectRevert(abi.encodeWithSignature("LossGreaterThanStrategyTotalDebt()"));
        vault.report(0, 0, 1, 0);
        /// 1 ETH of `loss` is gt. 0 ETH of balance

        deal({token: USDC, to: address(lossyStrategy), give: 1 * _1_USDC});

        /// provide strategy with 1 USDC
        vm.expectRevert(abi.encodeWithSignature("LossGreaterThanStrategyTotalDebt()"));
        vault.report(0, 0, uint128(11 * _1_USDC / 10), 0);
        /// 1.1 ETH of `loss` is gt. 1 ETH of balance

        /// Test assess fees twice in same block.timestamp
        vm.warp(block.timestamp + 1);
        vault.report(1, 1, 0, 0);
        vm.expectRevert(abi.encodeWithSignature("FeesAlreadyAssesed()"));
        vault.report(1, 1, 0, 0);
    }

    ////////////////////////////////////////////////////////////////
    ///                 TEST report() POSITIVES                  ///
    ////////////////////////////////////////////////////////////////
    function testMaxApyVaultV2__ReportPositives() public {
        /// *************** 🔹 Setup 🔹 *************** ///
        MockLossyUSDCStrategy lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC, makeAddr("strategist"));

        vault.addStrategy(address(lossyStrategy), 4000, type(uint96).max, 0, 0);

        _deposit(users.alice, vault, 100 * _1_USDC);

        /// alice deposits 100 ETH

        vm.startPrank(address(lossyStrategy));
        /// *************** 🔸 Tests 🔸 *************** ///

        /// ⭕️ SCENARIO 1: Execute initial report to validate distribution of funds
        /// - Report 0 `gain`, 0 `loss`, 0 `debtPayment`
        /// - Assert 0 loss is reported
        /// - Assert 0 fees are assessed due to `gain == 0`
        /// - Assert strategy's `strategyTotalRealizedGain` is 0
        /// - Assert strategy's `strategyTotalDebt` increases by expected `credit`
        /// - Assert `credit` > `totalReportedAmount`:
        ///     - totalIdle increase by difference between `credit` and `totalReportedAmount`
        ///     - funds are transferred from vault to strategy
        /// - Assert `strategyLastReport` and vault's `lastReport` gets updated with current `block.timestamp`
        /// - Assert expected `debt` value is returned
        vm.expectEmit();
        emit StrategyReported(
            address(lossyStrategy),
            0,
            /// realizedgain
            0,
            /// unrealized gain
            0,
            /// loss
            0,
            /// debtPayment
            0,
            /// strategyTotalRealizedGain
            0,
            /// strategyTotalLoss
            uint128(40 * _1_USDC),
            /// strategyTotalDebt
            uint128(40 * _1_USDC),
            /// credit
            4000
        );
        /// strategyDebtRatio

        uint256 debt = vault.report(0, 0, 0, 0);

        StrategyData memory strategyData = vault.strategies(address(lossyStrategy));

        /// Assert 0 loss is reported --> none of `strategyDebtRatio`, `debtRatio`, `strategyTotalDebt`,
        // `strategyTotalLoss`, vault `totalDebt` were modified
        assertEq(strategyData.strategyDebtRatio, 4000);
        assertEq(vault.debtRatio(), 4000);
        assertEq(strategyData.strategyTotalDebt, 40 * _1_USDC);
        assertEq(strategyData.strategyTotalLoss, 0);
        assertEq(vault.totalDebt(), 40 * _1_USDC);

        /// Assert 0 fees are assessed due to `gain == 0`.
        /// - Strategy is expected to hold 40 * _1_USDC (if more, fees were earned)
        /// - Treasury is expected to have 0 balance due to no earned fees
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy)), 40 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(TREASURY)), 0 * _1_USDC);

        /// Assert strategy's `strategyTotalRealizedGain` is 0
        assertEq(strategyData.strategyTotalRealizedGain, 0);

        /// - Assert strategy's `strategyTotalDebt` increases by expected `credit`
        /// already checked before

        /// - Assert vault's `strategyTotalDebt` increases by expected `credit`

        /// - Assert `credit` > `totalReportedAmount`:
        ///     - totalIdle increase by difference between `credit` and `totalReportedAmount`
        ///     - funds are transferred from vault to strategy --> already checked before
        assertEq(vault.totalIdle(), 60 * _1_USDC);

        /// - Assert `strategyLastReport` and vault's `lastReport` gets updated with current `block.timestamp`
        assertEq(strategyData.strategyLastReport, block.timestamp);
        assertEq(vault.lastReport(), block.timestamp);
        /// - Assert expected `debt` value is returned
        assertEq(debt, 0);
        /// no outstanding debt expected to be returned

        /// ⭕️ SCENARIO 2: Strategy reports 1 ETH loss
        /// - Report 0 `gain`, 1 ETH `loss`, 0 `debtPayment`
        /// - Assert `strategyDebtRatio` decreases by computed `ratioChange`
        /// - Assert vault `debtRatio` decreases by computed `ratioChange`
        /// - Assert `strategyTotalLoss` increases by loss reported
        /// - Assert `strategyTotalDebt` decreases by loss reported
        /// - Assert `totalDebt` decreases by loss reported
        /// - Assert `strategyTotalRealizedGain` keeps at 0
        /// - Assert `debt` is gt 0
        ///     - Loss reported modifies `_totalAssets()`, hence changing `_computeDebtLimit()` in `_debtOutstanding()`
        ///       calculation and making strategy owe a small amount to the vault
        /// - Assert `debtPayment` is 0 due to fetching `Math.min(debtPayment, debt)`
        /// - Ensure balances keep the same (`credit` and `totalReportedAmount` are equal, no transfers get executed)
        /// - Assert `strategyLastReport` and vault's `lastReport` gets updated with current `block.timestamp`
        uint256 snapshotId = vm.snapshot();

        StrategyData memory previousStrategyData = vault.strategies(address(lossyStrategy));
        uint256 previousVaultDebtRatio = vault.debtRatio();
        uint256 previousVaultTotalDebt = vault.totalDebt();
        uint256 previousVaultBalance = IERC20(USDC).balanceOf(address(vault));
        uint256 previousStrategyBalance = IERC20(USDC).balanceOf(address(lossyStrategy));

        vm.recordLogs();

        /// record StrategyReported() event

        debt = vault.report(0, 0, uint128(1 * _1_USDC), 0);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        strategyData = vault.strategies(address(lossyStrategy));
        uint256 expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategy), 1 * _1_USDC);
        /// - Assert `strategyDebtRatio` decreases by computed `ratioChange`
        assertEq(strategyData.strategyDebtRatio, previousStrategyData.strategyDebtRatio - expectedRatioChange);
        /// - Assert vault `debtRatio` decreases by computed `ratioChange`
        assertEq(vault.debtRatio(), previousVaultDebtRatio - expectedRatioChange);
        /// - Assert `strategyTotalLoss` increases by loss reported
        assertEq(strategyData.strategyTotalLoss, previousStrategyData.strategyTotalLoss + 1 * _1_USDC);
        /// - Assert `strategyTotalDebt` decreases by loss reported
        assertEq(strategyData.strategyTotalDebt, previousStrategyData.strategyTotalDebt - 1 * _1_USDC);
        /// - Assert `totalDebt` decreases by loss reported
        assertEq(vault.totalDebt(), previousVaultTotalDebt - 1 * _1_USDC);
        /// - Assert `strategyTotalRealizedGain` keeps at 0
        assertEq(strategyData.strategyTotalRealizedGain, 0);
        /// - Assert `debt` is gt 0
        assertGt(debt, 0);
        /// - Assert `debtPayment` is 0 due to fetching `Math.min(debtPayment, debt)`
        //assertEq(entries[0].topics[2], 0);
        /// - Ensure balances keep the same (`credit` and `totalReportedAmount` are equal, no transfers get executed)
        assertEq(previousVaultBalance, IERC20(USDC).balanceOf(address(vault)));
        assertEq(previousStrategyBalance, IERC20(USDC).balanceOf(address(lossyStrategy)));
        /// - Assert `strategyLastReport` and vault's `lastReport` gets updated with current `block.timestamp`
        assertEq(block.timestamp, strategyData.strategyLastReport);
        assertEq(block.timestamp, vault.lastReport());

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 3: Strategy reports 100 ETH gain
        /// Goal: test fees assesment
        /// - Assert vault management fee is 2% of reported yield
        /// - Assert strategist fee is 1.5% of reported yield
        /// - Assert vault performance fee is 2% of reported yield
        /// - Assert shares are transferred to strategy's strategist
        /// - Assert remaining shares are transferred to treasury
        /// - Assert 100 USDC are transferred from strategy to vault
        /// - Assert 100 USDC are transferred from strategy to vault
        ///     - Strategy balance reduces 100 USDC
        ///     - Vault balance increases 100 USDC
        ///     - Vault `totalIdle` increases by 100 USDC

        snapshotId = vm.snapshot();

        vm.startPrank(users.alice);

        /// Add a 1.5% performance fee for strategist
        vault.updateStrategyData(address(lossyStrategy), 4000, type(uint96).max, 0, 150);
        vm.stopPrank();
        vm.startPrank(address(lossyStrategy));

        vm.warp(block.timestamp + 100);

        deal({token: USDC, to: address(lossyStrategy), give: 100 * _1_USDC});

        /// mock 100 USDC gain in strategy

        previousVaultBalance = IERC20(USDC).balanceOf(address(vault));
        previousStrategyBalance = IERC20(USDC).balanceOf(address(lossyStrategy));

        vm.recordLogs();

        /// record FeesReported() event

        debt = vault.report(uint128(100 * _1_USDC), uint128(100 * _1_USDC), 0, 0);

        entries = vm.getRecordedLogs();

        uint256 expectedShares = _calculateExpectedShares(2 * _1_USDC + 15 * _1_USDC / 10 + 10 * _1_USDC);
        uint256 expectedStrategistFees = _calculateExpectedStrategistFees(
            15 * _1_USDC / 10, expectedShares, 2 * _1_USDC + 15 * _1_USDC / 10 + 10 * _1_USDC
        );

        /// - Assess vault management fee is 2% of reported yield
        //assertEq(2 * _1_USDC, uint256(entries[3].topics[1]));
        /// - Assess strategist fee is 1.5% of reported yield
        //assertEq(1.5 * _1_USDC, uint256(entries[3].topics[3]));
        /// - Assess vault performance fee is 2% of reported yield
        //assertEq(10 * _1_USDC, uint256(entries[3].topics[2]));
        /// - Assert shares are transferred to strategy's strategist
        assertEq(vault.balanceOf(lossyStrategy.strategist()), expectedStrategistFees);
        /// - Assert remaining shares are transferred to treasury
        assertEq(vault.balanceOf(vault.treasury()), expectedShares - expectedStrategistFees);
        /// - Assert 100 USDC are transferred from strategy to vault
        assertEq(IERC20(USDC).balanceOf(address(vault)), previousVaultBalance + 100 * _1_USDC);
        /// - Assert Strategy balance reduces 100 USDC
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy)), previousStrategyBalance - 100 * _1_USDC);
        /// - Assert vault `totalIdle` increases by 100 USDC
        assertEq(vault.totalIdle(), 60 * _1_USDC + 100 * _1_USDC);
        /// 60 * _1_USDC --> previous expected `totalIdle`
        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 4: Strategy reports  ETH gain, 40 ETH of debt Payment
        /// Goal: test debt payment
        /// - Assert debt payment is properly set
        ///     - We report 40 ETH as debt payment, but a max debt outstanding of 39.9 ETH is expected (0.1% of 100 ETH (totalAssets) -> 0.1 ETH
        ///       max can be held in vault, currently we have 40 ETH deployed so expected debt payment is 39.9 ETH)
        /// - Assert `strategyTotalDebt` is reduced by expected `debtPayment`
        /// - Assert vault `totalDebt` is reduced by expected `debtPayment`
        /// - Assert strategy balance is reduced by expected `debtPayment` and transferred to vault
        /// - Assert vault balance is increased by expected `debtPayment` and transferred from strategy

        snapshotId = vm.snapshot();
        vm.startPrank(users.alice);

        /// Update debtRatio to 0.1% so that `debtPayment` is != 0
        vault.updateStrategyData(
            address(lossyStrategy),
            10,
            /// 0.1%
            type(uint96).max,
            0,
            150
        );

        vm.startPrank(address(lossyStrategy));

        previousVaultBalance = IERC20(USDC).balanceOf(address(vault));
        previousStrategyBalance = IERC20(USDC).balanceOf(address(lossyStrategy));
        previousStrategyData = vault.strategies(address(lossyStrategy));
        debt = vault.report(0, 0, 0, uint128(40 * _1_USDC));

        /// report 40 ETH of `debtPayment`

        /// - Assert `strategyTotalDebt` is reduced by expected `debtPayment`
        assertEq(vault.strategies(address(lossyStrategy)).strategyTotalDebt, 100 * _1_USDC * 10 / 10000);
        /// - Assert vault `totalDebt` is reduced by expected `debtPayment`
        assertEq(vault.totalDebt(), 100 * _1_USDC * 10 / 10000);
        /// - Assert strategy balance is reduced by expected `debtPayment` and transferred to vault
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy)), 100 * _1_USDC * 10 / 10000);
        /// - Assert vault balance is increased by expected `debtPayment` and transferred from strategy
        assertEq(
            IERC20(USDC).balanceOf(address(vault)), previousVaultBalance + 40 * _1_USDC - 100 * _1_USDC * 10 / 10000
        );

        vm.revertTo(snapshotId);

        /// ⭕️ SCENARIO 5: Test vault in shutdown mode
        /// Goal: test shutdownMode and a high strategyMinDebtPerHarvest
        /// - Assert creditAvailable is 0
        /// - Assert 40 ETH are transferred back to vault (check vault and strategy balances)
        /// - Assert returned debt is vault's `totalAssets()`

        vm.startPrank(users.alice);

        vault.setEmergencyShutdown(true);

        vm.startPrank(address(lossyStrategy));
        lossyStrategy.setEstimatedTotalAssets(40 * _1_USDC);

        vm.recordLogs();

        /// record FeesReported() event
        previousVaultBalance = IERC20(USDC).balanceOf(address(vault));
        previousStrategyBalance = IERC20(USDC).balanceOf(address(lossyStrategy));
        debt = vault.report(0, 0, 0, uint128(40 * _1_USDC));
        /// report 40 ETH of `debtPayment`

        entries = vm.getRecordedLogs();

        /// - Assert creditAvailable is 0
        //assertEq(entries[1].topics[3], 0);
        /// - Assert 40 ETH are transferred back to vault (check vault and strategy balances)
        assertEq(IERC20(USDC).balanceOf(address(lossyStrategy)), previousStrategyBalance - 40 * _1_USDC);
        assertEq(IERC20(USDC).balanceOf(address(vault)), previousVaultBalance + 40 * _1_USDC);
        /// - Assert returned debt is vault's `estimatedTotalAssets`
        assertEq(vault.totalAccountedAssets(), 100 * _1_USDC);
        assertEq(vault.totalAssets(), 140 * _1_USDC);
    }
}
