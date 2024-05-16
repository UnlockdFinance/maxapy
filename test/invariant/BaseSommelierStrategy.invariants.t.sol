// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    BaseSommelierStrategyHandler,
    BaseSommelierStrategyWrapper,
    MockERC20
} from "./handlers/BaseSommelierStrategyHandler.t.sol";
import { MaxApyVaultV2Handler, MaxApyVaultV2 } from "./handlers/MaxApyVaultV2Handler.t.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import { MockCellar } from "../mock/MockCellar.sol";

contract BaseSommelierStrategyInvariants is StdInvariant, Test {
    MaxApyVaultV2Handler mvh;
    BaseSommelierStrategyHandler bsh;

    function setUp() public {
        MockERC20 _token = new MockERC20("MockWETH", "MW", 18);
        MaxApyVaultV2 _vault = new MaxApyVaultV2(address(_token), "MaxApyVault", "max", address(1));

        ProxyAdmin _proxyAdmin = new ProxyAdmin();
        BaseSommelierStrategyWrapper _implementation = new BaseSommelierStrategyWrapper();

        MockCellar _underlyingCellar = new MockCellar(address(_token), "Sommelier Cellar", "SC", true, 0);

        address[] memory keepers = new address[](1);
        keepers[0] = address(this);

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(_vault),
                keepers,
                bytes32(abi.encode("MaxApy Some WETH Strategy")),
                address(this),
                _underlyingCellar
            )
        );

        BaseSommelierStrategyWrapper _strategy = BaseSommelierStrategyWrapper(address(_proxy));
        _vault.addStrategy(address(_strategy), 6000, type(uint256).max, 0, 200);
        mvh = new MaxApyVaultV2Handler(_vault, _token);
        bsh = new BaseSommelierStrategyHandler(_vault, _strategy, _token);

        _strategy.grantRoles(address(bsh),_strategy.KEEPER_ROLE());
        _strategy.grantRoles(address(bsh),_strategy.VAULT_ROLE());
        _strategy.setAutopilot(true);
        _vault.setAutopilotEnabled(true);

        targetContract(address(mvh));
        targetContract(address(bsh));

        bytes4[] memory vaultSelectors = new bytes4[](2);
        vaultSelectors[0] = mvh.deposit.selector;
        vaultSelectors[1] = mvh.redeem.selector;
        //vaultSelectors[2] = mvh.withdraw.selector;

        targetSelector(FuzzSelector({ addr: address(mvh), selectors: vaultSelectors }));

        bytes4[] memory strategySelectors = bsh.getEntryPoints();
        targetSelector(FuzzSelector({ addr: address(bsh), selectors: strategySelectors }));

        excludeSender(address(_vault));
        excludeSender(address(_strategy));
        excludeSender(address(_underlyingCellar));
    }

    function invariantBaseSommelierStrategy__VaultAccounting() public {
        assertEq(mvh.actualAssets(), mvh.expectedAssets(), "invariant: redeem assets");
        assertEq(mvh.actualShares(), mvh.expectedShares(), "invariant: deposit shares");
    }

    function invariantBaseSommelierStrategy__AssetEstimation() public {
        assertEq(bsh.actualEstimatedTotalAssets(), bsh.expectedEstimatedTotalAssets(), "invariant: estimated assets");
    }

    function invariantBaseSommelierStrategy__CallSummary() public view {
        mvh.callSummary();
        bsh.callSummary();
    }
}
