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
import {Tokens} from "../test/helpers/Tokens.sol";


import {YearnMaticUSDCStakingStrategyWrapper} from "../test/mock/YearnMaticUSDCStakingStrategyWrapper.sol";

contract DeploymentScript is Script, ConvexPools, OwnableRoles, Tokens {
    ////////////////////////////////////////////////////////////////
    ///                      CONSTANTS                           ///
    ////////////////////////////////////////////////////////////////
    address public constant YVAULT_USDC_POLYGON = 0xF54a15F6da443041Bb075959EA66EE47655DDFcA;

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy; 
    IMaxApyVaultV2 public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function run() public {
        address [] memory keepers = new address[](3);
        // use another private key here, dont use a keeper account for deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
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
        MaxApyVaultV2 vaultDeployment = new MaxApyVaultV2(USDC_POLYGON, "MaxApyUSDCVault", "maxApy", treasury);

        console.log("MAXAPY VAULT Deployed to : ",address(vaultDeployment));


        vault = IMaxApyVaultV2(address(vaultDeployment));
        // grant roles
        vault.grantRoles(vaultAdmin, vault.ADMIN_ROLE());
        vault.grantRoles(vaultEmergencyAdmin, vault.EMERGENCY_ADMIN_ROLE());

        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin();

        // Deploy strategy
        console.log("Deploying YEARN STRATEGY... ");

        YearnMaticUSDCStakingStrategyWrapper implementation1 = new YearnMaticUSDCStakingStrategyWrapper();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Matic USDC Staking Strategy")),
                strategyAdmin,
                YVAULT_USDC_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy = IStrategyWrapper(address(_proxy));
        strategy.grantRoles(strategyAdmin, strategy.ADMIN_ROLE());
        strategy.grantRoles(strategyEmergencyAdmin, strategy.EMERGENCY_ADMIN_ROLE());

        console.log("YEARN STRATEGY Deployed to : ",address(strategy));

        // Add astrategy
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
    }


}