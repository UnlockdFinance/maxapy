// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import {BaseTest, IERC20, Vm, console} from "../test/base/BaseTest.t.sol";
import {IStrategyWrapper} from "../test/interfaces/IStrategyWrapper.sol";
import {IMaxApyVaultV2} from "src/interfaces/IMaxApyVaultV2.sol";
import {MaxApyVaultV2, OwnableRoles} from "src/MaxApyVaultV2.sol";
import {StrategyData} from "src/helpers/VaultTypes.sol";
import {StrategyEvents} from "../test/helpers/StrategyEvents.sol";
import {ICurve} from "src/interfaces/ICurve.sol";
import {IUniswapV2Router02 as IRouter} from "src/interfaces/IUniswap.sol";
import {ConvexPools} from "../test/helpers/ConvexPools.sol";

import {ConvexdETHFrxETHStrategyWrapper} from "../test/mock/ConvexdETHFrxETHStrategyWrapper.sol";
import {ConvexdETHFrxETHStrategyEvents} from "../test/helpers/ConvexdETHFrxETHStrategyEvents.sol";

import {SommelierMorphoEthMaximizerStrategyWrapper} from "../test/mock/SommelierMorphoEthMaximizerStrategyWrapper.sol";
import {SommelierMorphoEthMaximizerStrategy} from
    "src/strategies/mainnet/WETH/sommelier/SommelierMorphoEthMaximizerStrategy.sol";

import {SommelierTurboStEthStrategy} from "src/strategies/mainnet/WETH/sommelier/SommelierTurboStEthStrategy.sol";
import {SommelierTurboStEthStrategyWrapper} from "../test/mock/SommelierTurboStEthStrategyWrapper.sol";

import {SommelierStEthDepositTurboStEthStrategyWrapper} from
    "../test/mock/SommelierStEthDepositTurboStEthStrategyWrapper.sol";

import {YearnWETHStrategyWrapper} from "../test/mock/YearnWETHStrategyWrapper.sol";

contract DeploymentScript is Script, ConvexPools, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                      CONSTANTS                           ///
    ////////////////////////////////////////////////////////////////
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CELLAR_WETH_MAINNET_MORPHO = 0xcf4B531b4Cde95BD35d71926e09B2b54c564F5b6;
    address public constant CELLAR_WETH_MAINNET_STETH = 0xfd6db5011b171B05E1Ea3b92f9EAcaEEb055e971;
    address public constant CELLAR_STETH_MAINNET = 0xc7372Ab5dd315606dB799246E8aA112405abAeFf;
    address public constant YVAULT_WETH_MAINNET = 0xa258C4606Ca8206D8aA700cE2143D7db854D168c;

    address public constant CURVE_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    IERC20 public constant crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public constant cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public constant frxEth = IERC20(0x5E8422345238F34275888049021821E8E08CAa1f);

    IRouter public constant SUSHISWAP_ROUTER = IRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy1; // yearn
    IStrategyWrapper public strategy2; // sommelier turbo steth
    IStrategyWrapper public strategy3; // sommelier steth deposit
    IStrategyWrapper public strategy4; // convex

    IMaxApyVaultV2 public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function run() public {
        address [] memory keepers = new address[](3);
        // use another private key here, dont use a keeper account for deployment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        keepers[0] = vm.envAddress("KEEPER1_ADDRESS");
        keepers[1] = vm.envAddress("KEEPER2_ADDRESS");
        keepers[2] = vm.envAddress("KEEPER3_ADDRESS");

        address vaultAdmin = vm.envAddress("VAULT_ADMIN_ADDRESS");
        address vaultEmergencyAdmin = vm.envAddress("VAULT_EMERGENCY_ADMIN_ADDRESS");
        address strategyAdmin = vm.envAddress("STRATEGY_ADMIN_ADDRESS");
        address strategyEmergencyAdmin = vm.envAddress("STRATEGY_EMERGENCY_ADMIN_ADDRESS");

        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);       

        console.log("Deploying MAXAPY VAULT... ");

        /// Deploy MaxApyVaultV2
        MaxApyVaultV2 vaultDeployment = new MaxApyVaultV2(WETH, "MaxApyWETHVault", "maxApy", treasury);

        console.log("MAXAPY VAULT Deployed to : ",address(vaultDeployment));


        vault = IMaxApyVaultV2(address(vaultDeployment));
        // grant roles
        vault.grantRoles(vaultAdmin, vault.ADMIN_ROLE());
        vault.grantRoles(vaultEmergencyAdmin, vault.EMERGENCY_ADMIN_ROLE());

        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin();

        // Deploy strategy1
        console.log("Deploying YEARN STRATEGY... ");

        YearnWETHStrategyWrapper implementation1 = new YearnWETHStrategyWrapper();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                strategyAdmin,
                YVAULT_WETH_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy1 = IStrategyWrapper(address(_proxy));
        strategy1.grantRoles(strategyAdmin, strategy1.ADMIN_ROLE());
        strategy1.grantRoles(strategyEmergencyAdmin, strategy1.EMERGENCY_ADMIN_ROLE());

        console.log("YEARN STRATEGY Deployed to : ",address(strategy1));


        // Deploy strategy2

        console.log("Deploying SOMMELIER TURBO-ST-ETH STRATEGY... ");

        SommelierTurboStEthStrategyWrapper implementation2 = new SommelierTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation2),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                strategyAdmin,
                CELLAR_WETH_MAINNET_STETH
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy2 = IStrategyWrapper(address(_proxy));
        strategy2.grantRoles(strategyAdmin, strategy1.ADMIN_ROLE());
        strategy2.grantRoles(strategyEmergencyAdmin, strategy2.EMERGENCY_ADMIN_ROLE());

        console.log("SOMMELIER TURBO-ST-ETH STRATEGY deployed to: ", address(strategy2));

        // Deploy strategy3
        console.log("Deploying SOMMELIER (ST-ETH-DEPOSIT) TURBO-ST-ETH STRATEGY... ");

        SommelierStEthDepositTurboStEthStrategyWrapper implementation3 =
            new SommelierStEthDepositTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation3),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                strategyAdmin,
                CELLAR_STETH_MAINNET,
                CURVE_POOL
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));


        strategy3 = IStrategyWrapper(address(_proxy));
        strategy3.grantRoles(strategyAdmin, strategy1.ADMIN_ROLE());
        strategy3.grantRoles(strategyEmergencyAdmin, strategy3.EMERGENCY_ADMIN_ROLE());


        console.log("SOMMELIER (ST-ETH-DEPOSIT) deployed to : ", address(strategy3));

        // Deploy strategy4

        console.log("Deploying CONVEX STRATEGY... ");

        ConvexdETHFrxETHStrategyWrapper implementation4 = new ConvexdETHFrxETHStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation4),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address)",
                address(vault),
                keepers,
                strategyAdmin,
                bytes32(abi.encode("MaxApy dETH<>frxETH Strategy")),
                DETH_FRXETH_CURVE_POOL,
                ETH_FRXETH_CURVE_POOL,
                address(SUSHISWAP_ROUTER)
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));

        strategy4 = IStrategyWrapper(address(_proxy));

        console.log("CONVEX STRATEGY deployed to : ", address(strategy4));

        // Add all the strategies
        vault.addStrategy(address(strategy1), 2250, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy2), 2250, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy3), 2250, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy4), 2250, type(uint72).max, 0, 0);

    }


}