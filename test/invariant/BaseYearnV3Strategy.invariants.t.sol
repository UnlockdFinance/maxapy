// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    BaseYearnV3StrategyHandler,
    BaseYearnV3StrategyWrapper,
    MockERC20
} from "./handlers/BaseYearnV3StrategyHandler.t.sol";
import { MaxApyVaultHandler, MaxApyVault } from "./handlers/MaxApyVaultHandler.t.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import { MockYVaultV3 } from "../mock/MockYVaultV3.sol";

contract BaseYearnV3StrategyInvariants is StdInvariant, Test {
    MaxApyVaultHandler mvh;
    BaseYearnV3StrategyHandler byh;

    function setUp() public {
        MockERC20 _token = new MockERC20("MockWETH", "MW", 18);
        MaxApyVault _vault = new MaxApyVault(address(_token), "MaxApyVault", "max", address(1));

        ProxyAdmin _proxyAdmin = new ProxyAdmin();
        BaseYearnV3StrategyWrapper _implementation = new BaseYearnV3StrategyWrapper();

        MockYVaultV3 _underlyingYvault = new MockYVaultV3(address(_token), "Yearn Vault", "YV", true, 0);

        address[] memory keepers = new address[](1);
        keepers[0] = address(this);

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(_vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn WETH Strategy")),
                address(this),
                _underlyingYvault
            )
        );

        BaseYearnV3StrategyWrapper _strategy = BaseYearnV3StrategyWrapper(address(_proxy));
        _vault.addStrategy(address(_strategy), 6000, type(uint256).max, 0, 200);
        mvh = new MaxApyVaultHandler(_vault, _token);
        byh = new BaseYearnV3StrategyHandler(_vault, _strategy, _token);

        _strategy.grantRoles(address(byh), _strategy.KEEPER_ROLE());
        _strategy.grantRoles(address(byh), _strategy.VAULT_ROLE());
        _strategy.setAutopilot(true);
        _vault.setAutopilotEnabled(true);

        targetContract(address(mvh));
        targetContract(address(byh));

        bytes4[] memory vaultSelectors = mvh.getEntryPoints();

        targetSelector(FuzzSelector({ addr: address(mvh), selectors: vaultSelectors }));

        bytes4[] memory strategySelectors = byh.getEntryPoints();
        targetSelector(FuzzSelector({ addr: address(byh), selectors: strategySelectors }));

        excludeSender(address(_vault));
        excludeSender(address(_strategy));
        excludeSender(address(_underlyingYvault));

        vm.label(address(_token), "WETH");
        vm.label(address(_strategy), "BaseYearnV3Strategy");
        vm.label(address(_vault), "VAULT");
        vm.label(address(mvh), "MVH");
    }

    function invariantBaseYearnV3Strategy__VaultAccounting() public {
        assertEq(mvh.actualAssets(), mvh.expectedAssets());
        assertEq(mvh.actualShares(), mvh.expectedShares());
    }

    function invariantBaseYearnV3Strategy__AssetEstimation() public {
        assertGe(byh.actualEstimatedTotalAssets(), byh.expectedEstimatedTotalAssets());
    }

    function invariantBaseYearnV3Strategy__CallSummary() public view {
        mvh.callSummary();
        byh.callSummary();
    }
}
