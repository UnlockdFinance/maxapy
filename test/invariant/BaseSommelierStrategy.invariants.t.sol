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
import { BaseTest } from "../base/BaseTest.t.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

contract BaseSommelierStrategyInvariants is StdInvariant, BaseTest {
    MaxApyVaultV2Handler mvh;
    BaseSommelierStrategyHandler bsh;

    /// List of mainnet weth cellars to play with
    address[7] cellars = [
        0xcf4B531b4Cde95BD35d71926e09B2b54c564F5b6, // morpho maximizer
        0xdAdC82e26b3739750E036dFd9dEfd3eD459b877A, // eeth v2
        0x19B8D8FC682fC56FbB42653F68c7d48Dd3fe597E, // eth x
        0x27500De405a3212D57177A789E30bb88b0AdbeC5, // ezeth
        0x1dffb366b5c5A37A12af2C127F31e8e0ED86BDbe, // rseth
        0xfd6db5011b171B05E1Ea3b92f9EAcaEEb055e971, // steth
        0xd33dAd974b938744dAC81fE00ac67cb5AA13958E // sweth
    ];

    function setUp() public {
        super._setUp("MAINNET");
        vm.rollFork(19_867_327);

        uint256 _cellarSeed;
        _cellarSeed = bound(_cellarSeed, 0, cellars.length - 1);
        address _underlyingCellar = cellars[_cellarSeed];

        MockERC20 _token = MockERC20(WETH_MAINNET);
        MaxApyVaultV2 _vault = new MaxApyVaultV2(address(_token), "MaxApyVault", "max", address(1));

        ProxyAdmin _proxyAdmin = new ProxyAdmin();
        BaseSommelierStrategyWrapper _implementation = new BaseSommelierStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

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

        targetContract(address(mvh));
        targetContract(address(bsh));

        bytes4[] memory selectors = mvh.getEntryPoints();
        targetSelector(FuzzSelector({ addr: address(mvh), selectors: selectors }));

        selectors = bsh.getEntryPoints();
        targetSelector(FuzzSelector({ addr: address(bsh), selectors: selectors }));

        excludeSender(address(_vault));
        excludeSender(address(_strategy));
    }

    function invariantBaseSommelierStrategy__CallSummary() public view {
        mvh.callSummary();
        bsh.callSummary();
    }
}
