// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    BaseSommelierStrategyHandler, BaseSommelierStrategyWrapper
} from "./handlers/BaseSommelierStrategyHandler.t.sol";
import { MaxApyVaultHandler, MaxApyVault } from "./handlers/MaxApyVaultHandler.t.sol";
import { SetUp } from "./helpers/SetUp.t.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import { MockCellar } from "../mock/MockCellar.sol";
import { IStrategyHandler } from "../interfaces/IStrategyHandler.sol";
import { IStrategyWrapper } from "../interfaces/IStrategyWrapper.sol";

contract BaseSommelierStrategyInvariants is SetUp {
    function setUp() public {
        _setUpToken();
        _setUpVault();

        ProxyAdmin _proxyAdmin = new ProxyAdmin();
        BaseSommelierStrategyWrapper _implementation = new BaseSommelierStrategyWrapper();

        MockCellar _underlyingCellar = new MockCellar(address(token), "Sommelier Cellar", "SC", true, 0);

        address[] memory keepers = new address[](1);
        keepers[0] = address(this);

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Some WETH Strategy")),
                address(this),
                _underlyingCellar
            )
        );

        BaseSommelierStrategyWrapper _strategy = BaseSommelierStrategyWrapper(address(_proxy));
        vaultHandler = new MaxApyVaultHandler(vault, token);
        BaseSommelierStrategyHandler _strategyHandler = new BaseSommelierStrategyHandler(vault, _strategy, token);

        _setUpStrategy(IStrategyWrapper(address(_strategy)), IStrategyHandler(address(_strategyHandler)));

        bytes4[] memory vaultSelectors = vaultHandler.getEntryPoints();

        targetSelector(FuzzSelector({ addr: address(vaultHandler), selectors: vaultSelectors }));

        excludeSender(address(_underlyingCellar));

        vm.label(address(_strategy), "BaseSommelierStrategy");
        vm.label(address(strategyHandler), "BSH");
    }

    function invariantBaseSommelierStrategy_vaultAccounting() public {
        vaultHandler.INVARIANT_A_SHARE_PREVIEWS();
        vaultHandler.INVARIANT_B_ASSET_PREVIEWS();
    }

    function invariantBaseSommelierStrategy__AssetEstimation() public {
        strategyHandler.INVARIANT_A_ESTIMATED_TOTAL_ASSETS();
    }

    function invariantBaseSommelierStrategy__CallSummary() public view {
        vaultHandler.callSummary();
        strategyHandler.callSummary();
    }
}
