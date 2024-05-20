// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    BaseYearnV2StrategyHandler,
    BaseYearnV2StrategyWrapper,
    MockERC20
} from "./handlers/BaseYearnV2StrategyHandler.t.sol";
import { MaxApyVaultV2Handler, MaxApyVaultV2 } from "./handlers/MaxApyVaultV2Handler.t.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import { MockYVaultV2 } from "../mock/MockYVaultV2.sol";

contract BaseYearnV2StrategyInvariants is StdInvariant, Test {
    MaxApyVaultV2Handler mvh;
    BaseYearnV2StrategyHandler byh;

    function setUp() public {
        MockERC20 _token = new MockERC20("MockWETH", "MW", 18);
        MaxApyVaultV2 _vault = new MaxApyVaultV2(address(_token), "MaxApyVault", "max", address(1));

        ProxyAdmin _proxyAdmin = new ProxyAdmin();
        BaseYearnV2StrategyWrapper _implementation = new BaseYearnV2StrategyWrapper();

        MockYVaultV2 _underlyingYvault = new MockYVaultV2(address(_token), "Yearn Vault", "YV");

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

        BaseYearnV2StrategyWrapper _strategy = BaseYearnV2StrategyWrapper(address(_proxy));
        _vault.addStrategy(address(_strategy), 6000, type(uint256).max, 0, 200);
        mvh = new MaxApyVaultV2Handler(_vault, _token);
        byh = new BaseYearnV2StrategyHandler(_vault, _strategy, _token);

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
    }

    function invariantBaseYearnV2Strategy__VaultAccounting() public {
        assertEq(mvh.actualAssets(), mvh.expectedAssets());
        assertEq(mvh.actualShares(), mvh.expectedShares());
    }

    function invariantBaseYearnV2Strategy__AssetEstimation() public {
        assertGe(byh.actualEstimatedTotalAssets(), byh.expectedEstimatedTotalAssets());
    }

    function invariantBaseYearnV2Strategy__CallSummary() public view {
        mvh.callSummary();
        byh.callSummary();
    }
}
