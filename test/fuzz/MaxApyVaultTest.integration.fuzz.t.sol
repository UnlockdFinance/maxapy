// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import { BaseTest, IERC20, Vm, console } from "../base/BaseTest.t.sol";
import { IStrategyWrapper } from "../interfaces/IStrategyWrapper.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { StrategyEvents } from "../helpers/StrategyEvents.sol";
import { ICurve } from "src/interfaces/ICurve.sol";
import { IUniswapV2Router02 as IRouter } from "src/interfaces/IUniswap.sol";
import { ConvexPools } from "../helpers/ConvexPools.sol";

// Convex
import { ConvexdETHFrxETHStrategyWrapper } from "../mock/ConvexdETHFrxETHStrategyWrapper.sol";

// Sommelier
import { SommelierMorphoEthMaximizerStrategyWrapper } from "../mock/SommelierMorphoEthMaximizerStrategyWrapper.sol";
import { SommelierTurboStEthStrategyWrapper } from "../mock/SommelierTurboStEthStrategyWrapper.sol";
import { SommelierStEthDepositTurboStEthStrategyWrapper } from
    "../mock/SommelierStEthDepositTurboStEthStrategyWrapper.sol";
import { SommelierTurboDivEthStrategyWrapper } from "../mock/SommelierTurboDivEthStrategyWrapper.sol";
import { SommelierTurboSwEthStrategyWrapper } from "../mock/SommelierTurboSwEthStrategyWrapper.sol";

// Yearn v2
import { YearnWETHStrategyWrapper } from "../mock/YearnWETHStrategyWrapper.sol";

// Yearn v3
import { YearnAjnaWETHStakingStrategyWrapper } from "../mock/YearnAjnaWETHStakingStrategyWrapper.sol";
import { YearnV3WETHStrategyWrapper } from "../mock/YearnV3WETHStrategyWrapper.sol";
import { YearnV3WETH2StrategyWrapper } from "../mock/YearnV3WETH2StrategyWrapper.sol";
import { YearnCompoundV3WETHLenderStrategyWrapper } from "../mock/YearnCompoundV3WETHLenderStrategyWrapper.sol";

// Reverting strategy
import { MockRevertingStrategy } from "../mock/MockRevertingStrategy.sol";

// Vault fuzzer
import { MaxApyVaultFuzzer } from "./fuzzers/MaxApyVaultFuzzer.t.sol";
import { StrategyFuzzer } from "./fuzzers/StrategyFuzzer.t.sol";

// Import Random Number Generator
import { LibPRNG } from "solady/utils/LibPRNG.sol";

/// @dev Integration fuzz tests for the mainnet WETH vault
contract MaxApyV2IntegrationTest is BaseTest, StrategyEvents, ConvexPools {
    using LibPRNG for LibPRNG.PRNG;

    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////
    // Curve
    address public constant CURVE_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    // Sommelier Morpho Maximizer
    address public constant CELLAR_WETH_MAINNET_MORPHO = 0xcf4B531b4Cde95BD35d71926e09B2b54c564F5b6;
    // Sommelier StETh
    address public constant CELLAR_WETH_MAINNET_STETH = 0xfd6db5011b171B05E1Ea3b92f9EAcaEEb055e971;
    // Sommelier StETh(StEth deposit)
    address public constant CELLAR_STETH_MAINNET = 0xc7372Ab5dd315606dB799246E8aA112405abAeFf;
    // Sommelier DivEth
    address public constant CELLAR_BAL_MAINNET = 0x6c1edce139291Af5b84fB1e496c9747F83E876c9;
    address public BAL_LP_TOKEN = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
    // Sommelier SwEth
    address public constant CELLAR_WETH_MAINNET_SWETH = 0xd33dAd974b938744dAC81fE00ac67cb5AA13958E;

    // YearnV2 WETH
    address public constant YVAULT_WETH_MAINNET = 0xa258C4606Ca8206D8aA700cE2143D7db854D168c;
    // YearnV3 Ajna WETH Staking
    address public constant YVAULT_AJNA_WETH_MAINNET = 0x503e0BaB6acDAE73eA7fb7cf6Ae5792014dbe935;
    // YearnV3 WETH
    address public constant YVAULT_WETHV3_MAINNET = 0xc56413869c6CDf96496f2b1eF801fEDBdFA7dDB0;
    // YearnV3 WETH2
    address public constant YVAULT_WETHV3_2_MAINNET = 0xAc37729B76db6438CE62042AE1270ee574CA7571;
    // YearnV3 CompoundV3Lender
    address public constant YVAULT_WETH_COMPOUND_LENDER = 0xb1403908F772E4374BB151F7C67E88761a0Eb4f1;

    // Vault Fuzzer
    MaxApyVaultFuzzer public vaultFuzzer;
    // Strategies fuzzer
    StrategyFuzzer public strategyFuzzer;

    IERC20 public constant crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public constant cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public constant frxEth = IERC20(0x5E8422345238F34275888049021821E8E08CAa1f);

    IRouter public constant SUSHISWAP_ROUTER = IRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    address public TREASURY;

    ////////////////////////////////////////////////////////////////
    ///                      HELPER FUNCTION                     ///
    ////////////////////////////////////////////////////////////////
    function _dealStEth(address give, uint256 wethIn) internal returns (uint256 stEthOut) {
        vm.deal(give, wethIn);
        stEthOut = ICurve(CURVE_POOL).exchange{ value: wethIn }(0, 1, wethIn, 0);
        IERC20(ST_ETH_MAINNET).transfer(give, stEthOut >= wethIn ? wethIn : stEthOut);
    }

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy1; // yearn
    IStrategyWrapper public strategy2; // sommelier turbo steth
    IStrategyWrapper public strategy3; // sommelier steth deposit
    IStrategyWrapper public strategy4; // convex
    IStrategyWrapper public strategy5; // convex
    IStrategyWrapper public strategy6; // convex
    IStrategyWrapper public strategy7; // convex
    IStrategyWrapper public strategy8; // convex
    IStrategyWrapper public strategy9; // convex

    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function setUp() public {
        super._setUp("MAINNET");
        vm.rollFork(19_267_583);

        TREASURY = makeAddr("treasury");

        /// Deploy MaxApyVault
        MaxApyVault vaultDeployment = new MaxApyVault(WETH_MAINNET, "MaxApyWETHVault", "maxApy", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        // Deploy strategy1
        YearnWETHStrategyWrapper implementation1 = new YearnWETHStrategyWrapper();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                users.alice,
                YVAULT_WETH_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(YVAULT_WETH_MAINNET, "yVault");
        vm.label(address(proxy), "YearnWETHStrategy");
        strategy1 = IStrategyWrapper(address(_proxy));

        // Deploy strategy2
        SommelierTurboStEthStrategyWrapper implementation2 = new SommelierTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation2),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                users.alice,
                CELLAR_WETH_MAINNET_STETH
            )
        );
        vm.label(CELLAR_WETH_MAINNET_STETH, "Cellar");
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierTurbStEthStrategy");

        strategy2 = IStrategyWrapper(address(_proxy));

        // Deploy strategy3
        SommelierStEthDepositTurboStEthStrategyWrapper implementation3 =
            new SommelierStEthDepositTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation3),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                users.alice,
                CELLAR_STETH_MAINNET
            )
        );
        vm.label(CELLAR_STETH_MAINNET, "Cellar");
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierStEThDeposiTurbStEthStrategy");
        vm.label(ST_ETH_MAINNET, "StETH");

        strategy3 = IStrategyWrapper(address(_proxy));

        // Deploy strategy4
        ConvexdETHFrxETHStrategyWrapper implementation4 = new ConvexdETHFrxETHStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation4),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address)",
                address(vault),
                keepers,
                users.alice,
                bytes32(abi.encode("MaxApy dETH<>frxETH Strategy")),
                DETH_FRXETH_CURVE_POOL,
                ETH_FRXETH_CURVE_POOL,
                address(SUSHISWAP_ROUTER)
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "ConvexdETHFrxETHStrategy");

        strategy4 = IStrategyWrapper(address(_proxy));

        address[] memory strategyList = new address[](4);

        strategyList[0] = address(strategy1);
        strategyList[1] = address(strategy2);
        strategyList[2] = address(strategy3);
        strategyList[3] = address(strategy4);

        // Add all the strategies
        vault.addStrategy(address(strategy1), 2250, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy2), 2250, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy3), 2250, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy4), 2250, type(uint72).max, 0, 0);

        vm.label(address(WETH_MAINNET), "WETH");
        /// Alice approves vault for deposits
        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
        vm.startPrank(users.bob);
        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(users.alice);

        // deploy fuzzers
        strategyFuzzer = new StrategyFuzzer(strategyList, vault, WETH_MAINNET);
        vaultFuzzer = new MaxApyVaultFuzzer(vault, WETH_MAINNET);

        vault.grantRoles(address(strategyFuzzer), vault.ADMIN_ROLE());
        uint256 _keeperRole = strategy1.KEEPER_ROLE();

        strategy1.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy2.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy3.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy4.grantRoles(address(strategyFuzzer), _keeperRole);
    }

    function testFuzzMaxApyVault___DepositAndRedeemWithoutHarvests(
        uint256 actorSeed,
        uint256 assets,
        uint256 shares
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        actorSeedRNG.seed(actorSeed);
        vaultFuzzer.deposit(assets);
        vaultFuzzer.deposit(assets);
        vaultFuzzer.deposit(assets);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        vaultFuzzer.redeem(actorSeedRNG, shares);
    }

    function testFuzzMaxApyVault__DepositAndRedeemWithHarvests(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 assets,
        uint256 shares
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        LibPRNG.PRNG memory strategyRNG;
        actorSeedRNG.seed(actorSeed);
        strategyRNG.seed(strategySeed);

        vaultFuzzer.deposit(assets);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.deposit(assets);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.deposit(assets);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        vaultFuzzer.redeem(actorSeedRNG, shares);
    }

    function testFuzzMaxApyVault___MintAndWithdrawWithoutHarvests(
        uint256 actorSeed,
        uint256 assets,
        uint256 shares
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        actorSeedRNG.seed(actorSeed);
        vaultFuzzer.mint(shares);
        vaultFuzzer.mint(shares);
        vaultFuzzer.mint(shares);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
    }

    function testFuzzMaxApyVault__MintAndWithdrawWithHarvests(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 shares,
        uint256 assets
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        LibPRNG.PRNG memory strategySeedRNG;
        actorSeedRNG.seed(actorSeed);
        strategySeedRNG.seed(strategySeed);

        vaultFuzzer.mint(shares);
        strategyFuzzer.harvest(strategySeedRNG);
        vaultFuzzer.mint(shares);
        strategyFuzzer.harvest(strategySeedRNG);
        vaultFuzzer.mint(shares);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
        strategyFuzzer.harvest(strategySeedRNG);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
    }
}
