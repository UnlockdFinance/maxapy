// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import {IMaxApyVaultV2} from "src/interfaces/IMaxApyVaultV2.sol";
import {MaxApyVaultV2, OwnableRoles} from "src/MaxApyVaultV2.sol";
import {StrategyData} from "src/helpers/VaultTypes.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {MockToken} from "./mocks/MockToken.sol";


contract DeploymentScript is Script, OwnableRoles {
    
    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    MockStrategy public strategy; // yearn
    IMaxApyVaultV2 public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;
    MockToken public token;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function run() public {
        address [] memory keepers = new address[](3);
        // use another private key here, dont use a keeper account for deployment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        keepers[0] = vm.envAddress("KEEPER1_ADDRESS");
        keepers[1] = vm.envAddress("KEEPER2_ADDRESS");
        keepers[2] = vm.envAddress("KEEPER3_ADDRESS");

        address vaultAdmin = vm.envAddress("VAULT_ADMIN_ADDRESS");
        address vaultEmergencyAdmin = vm.envAddress("VAULT_EMERGENCY_ADMIN_ADDRESS");
        address strategyAdmin = vm.envAddress("STRATEGY_ADMIN_ADDRESS");
        address strategyEmergencyAdmin = vm.envAddress("STRATEGY_EMERGENCY_ADMIN_ADDRESS");

        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);       

        console.log("Deploying MOCK TOKEN...");

        token = new MockToken("Wrapped Ether", "WETH");
        token.mint(deployerAddress, 100_000 ether);
        token.mint(vaultAdmin, 100_000 ether);
        token.mint(vaultEmergencyAdmin, 100_000 ether);
        token.mint(strategyAdmin, 100_000 ether);
        token.mint(keepers[0], 100_000 ether);
        token.mint(keepers[1], 100_000 ether);
        token.mint(keepers[2], 100_000 ether);

        console.log("Deploying MAXAPY VAULT... ");

        /// Deploy MaxApyVaultV2
        MaxApyVaultV2 vaultDeployment = new MaxApyVaultV2(address(token), "MaxApyWETHVault", "maxWETH", treasury);

        console.log("MAXAPY VAULT Deployed to : ",address(vaultDeployment));


        vault = IMaxApyVaultV2(address(vaultDeployment));
        // grant roles
        vault.grantRoles(vaultAdmin, vault.ADMIN_ROLE());
        vault.grantRoles(vaultEmergencyAdmin, vault.EMERGENCY_ADMIN_ROLE());

        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin();

        // Deploy strategy
        console.log("Deploying MOCK STRATEGY... ");

        MockStrategy implementation = new MockStrategy();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                strategyAdmin
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy = MockStrategy(address(_proxy));
        strategy.grantRoles(strategyAdmin, strategy.ADMIN_ROLE());
        strategy.grantRoles(strategyEmergencyAdmin, strategy.EMERGENCY_ADMIN_ROLE());

        console.log("YEARN STRATEGY Deployed to : ",address(strategy));

        // Add strategy
        vault.addStrategy(address(strategy), 6000, type(uint72).max, 0, 0);
    }

}