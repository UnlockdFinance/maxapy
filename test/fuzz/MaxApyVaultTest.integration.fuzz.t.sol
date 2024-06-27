// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import { BaseTest, IERC20, Vm, console2 } from "../base/BaseTest.t.sol";
import { IStrategyWrapper } from "../interfaces/IStrategyWrapper.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { StrategyEvents } from "test/helpers/StrategyEvents.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { IUniswapV2Router02 as IRouter } from "src/interfaces/IUniswap.sol";
import { ConvexPools } from "test/helpers/ConvexPools.sol";
import { WETH_MAINNET, ST_ETH_MAINNET } from "test/helpers/Tokens.sol";

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
    address public constant YVAULT_WETH_COMPOUND_LENDER = 0x23eE3D14F09946A084350CC6A7153fc6eb918817;

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
        stEthOut = ICurveLpPool(CURVE_POOL).exchange{ value: wethIn }(0, 1, wethIn, 0);
        IERC20(ST_ETH_MAINNET).transfer(give, stEthOut >= wethIn ? wethIn : stEthOut);
    }

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IStrategyWrapper public strategy1; // yearn weth
    IStrategyWrapper public strategy2; // sommelier turbo steth
    IStrategyWrapper public strategy3; // sommelier steth deposit
    IStrategyWrapper public strategy4; // convex
    IStrategyWrapper public strategy5; // sommelier morpho eth
    IStrategyWrapper public strategy6; // sommelier turbo div eth
    IStrategyWrapper public strategy7; // sommelier sweth
    IStrategyWrapper public strategy8; // yearn ajna weth staking
    IStrategyWrapper public strategy9; // yearn v3 weth
    IStrategyWrapper public strategy10; // yearn v3 weth2
    IStrategyWrapper public strategy11; // yearn compound v3 weth lender

    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function setUp() public {
        super._setUp("MAINNET");
        vm.rollFork(19_425_883);

        TREASURY = makeAddr("treasury");

        /// Deploy MaxApyVault
        MaxApyVault vaultDeployment = new MaxApyVault(users.alice, WETH_MAINNET, "MaxApyWETHVault", "maxApy", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(users.alice);

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

        // Deploy strategy5
        SommelierMorphoEthMaximizerStrategyWrapper implementation5 = new SommelierMorphoEthMaximizerStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation5),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Morpho ETH Strategy")),
                users.alice,
                CELLAR_WETH_MAINNET_MORPHO
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierMorphoEthMaximizerStrategy");

        strategy5 = IStrategyWrapper(address(_proxy));

        // Deploy strategy6
        SommelierTurboDivEthStrategyWrapper implementation6 = new SommelierTurboDivEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation6),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("Sommelier Turbo Div ETH Strategy")),
                users.alice,
                CELLAR_BAL_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierTurboDivEthStrategy");

        strategy6 = IStrategyWrapper(address(_proxy));

        // Deploy strategy7
        SommelierTurboSwEthStrategyWrapper implementation7 = new SommelierTurboSwEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation7),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("Sommelier SwETH Strategy")),
                users.alice,
                CELLAR_WETH_MAINNET_SWETH
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierSwEthStrategy");

        strategy7 = IStrategyWrapper(address(_proxy));

        // Deploy strategy8
        YearnAjnaWETHStakingStrategyWrapper implementation8 = new YearnAjnaWETHStakingStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation8),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("Yearn Ajna WETH Stakingtrategy")),
                users.alice,
                YVAULT_AJNA_WETH_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnAjnaWETHStakingStrategy");

        strategy8 = IStrategyWrapper(address(_proxy));

        // Deploy strategy9
        YearnV3WETHStrategyWrapper implementation9 = new YearnV3WETHStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation9),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("Yearn v3 WETH Strategy")),
                users.alice,
                YVAULT_WETHV3_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnV3WETHStrategy");

        strategy9 = IStrategyWrapper(address(_proxy));

        // Deploy strategy10
        YearnV3WETH2StrategyWrapper implementation10 = new YearnV3WETH2StrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation10),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("Yearn v3 WETH2 Strategy")),
                users.alice,
                YVAULT_WETHV3_2_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnV3WETH2Strategy");

        strategy10 = IStrategyWrapper(address(_proxy));

        // Deploy strategy11
        YearnCompoundV3WETHLenderStrategyWrapper implementation11 = new YearnCompoundV3WETHLenderStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation11),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("Yearn Compound V3 WETH Lender")),
                users.alice,
                YVAULT_WETH_COMPOUND_LENDER
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnCompoundV3WETHLenderStrategy");

        strategy11 = IStrategyWrapper(address(_proxy));

        address[] memory strategyList = new address[](9);

        strategyList[0] = address(strategy1);
        strategyList[1] = address(strategy2);
        strategyList[2] = address(strategy3);
     //   strategyList[3] = address(strategy4);
        strategyList[3] = address(strategy5);
        strategyList[4] = address(strategy6);
        strategyList[5] = address(strategy7);
        strategyList[6] = address(strategy8);
        strategyList[7] = address(strategy9);
        // strategyList[9] = address(strategy10);
        strategyList[8] = address(strategy11);

        // Add all the strategies
        vault.addStrategy(address(strategy1), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy2), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy3), 700, type(uint72).max, 0, 0);
       // vault.addStrategy(address(strategy4), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy5), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy6), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy7), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy8), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy9), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy11), 700, type(uint72).max, 0, 0);

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
        strategy5.grantRoles(address(strategyFuzzer), _keeperRole);
    }

    function testFuzzMaxApyVault__DepositAndRedeemWithoutHarvests(
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

    function testFuzzMaxApyVault__DepositAndRedeemAfterExitStrategy(
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
        strategyFuzzer.exitStrategy(strategyRNG);
        vaultFuzzer.deposit(assets);
        strategyFuzzer.exitStrategy(strategyRNG);
        vaultFuzzer.deposit(assets);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        strategyFuzzer.exitStrategy(strategyRNG);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        vaultFuzzer.redeem(actorSeedRNG, shares);
    }

    function testFuzzMaxApyVault__DepositAndRedeemWithGainsAndLossesWithoutHarvests(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 gainsAndLossesSeed,
        uint256 assets,
        uint256 shares
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        LibPRNG.PRNG memory strategyRNG;
        LibPRNG.PRNG memory gainAndLossesRNG;

        actorSeedRNG.seed(actorSeed);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        strategyRNG.seed(strategySeed);
        gainAndLossesRNG.seed(gainsAndLossesSeed);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.deposit(assets);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.deposit(assets);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.deposit(assets);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        strategyFuzzer.loss(strategyRNG, gainAndLossesRNG.next());
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        vaultFuzzer.redeem(actorSeedRNG, shares);
    }

    function testFuzzMaxApyVault__DepositAndRedeemWithGainsAndLossesWithHarvests(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 gainsAndLossesSeed,
        uint256 assets,
        uint256 shares
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        LibPRNG.PRNG memory strategyRNG;
        LibPRNG.PRNG memory gainAndLossesRNG;

        actorSeedRNG.seed(actorSeed);
        strategyRNG.seed(strategySeed);
        gainAndLossesRNG.seed(gainsAndLossesSeed);

        vaultFuzzer.deposit(assets);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.deposit(assets);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.deposit(assets);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        strategyFuzzer.loss(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.redeem(actorSeedRNG, shares);
        vaultFuzzer.redeem(actorSeedRNG, shares);
    }

    function testFuzzMaxApyVault__MintAndWithdrawWithoutHarvests(
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

    function testFuzzMaxApyVault__MintAndWithdrawGainsAndLossesWithoutHarvests(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 gainsAndLossesSeed,
        uint256 shares,
        uint256 assets
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        LibPRNG.PRNG memory strategyRNG;
        LibPRNG.PRNG memory gainAndLossesRNG;

        actorSeedRNG.seed(actorSeed);
        strategyRNG.seed(strategySeed);
        gainAndLossesRNG.seed(gainsAndLossesSeed);

        vaultFuzzer.mint(shares);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.mint(shares);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.mint(shares);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
        strategyFuzzer.loss(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.withdraw(actorSeedRNG, assets);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
    }

    function testFuzzMaxApyVault__MintAndWithdrawGainsAndLossesWithHarvests(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 gainsAndLossesSeed,
        uint256 shares,
        uint256 assets
    )
        public
    {
        LibPRNG.PRNG memory actorRNG;
        LibPRNG.PRNG memory strategyRNG;
        LibPRNG.PRNG memory gainAndLossesRNG;
        
        console2.log("strategy 1: ", address(strategy1));
        console2.log("strategy 2: ", address(strategy2));
        console2.log("strategy 3: ", address(strategy3));
        console2.log("strategy 4: ", address(strategy5));
        console2.log("strategy 5: ", address(strategy4));
        console2.log("strategy 6: ", address(strategy4));
        console2.log("strategy 7 ", address(strategy4));
        console2.log("strategy 8: ", address(strategy4));
        console2.log("strategy 9: ", address(strategy4));
        console2.log("strategy 10: ", address(strategy4));

        actorRNG.seed(actorSeed);
        strategyRNG.seed(strategySeed);
        gainAndLossesRNG.seed(gainsAndLossesSeed);
        vaultFuzzer.mint(shares);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.mint(shares);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.mint(shares);
        console2.log("withdraw1");
        vaultFuzzer.withdraw(actorRNG, assets);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.loss(strategyRNG, gainAndLossesRNG.next());
        console2.log("withdraw2");
        vaultFuzzer.withdraw(actorRNG, assets);
        console2.log("withdraw3");
        vaultFuzzer.withdraw(actorRNG, assets);
        strategyFuzzer.harvest(strategyRNG);
    }

    function testFuzzMaxApyVault__RandomSequence(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 functionSeed,
        uint256 argumentsSeed
    )
        public
    {
        LibPRNG.PRNG memory actorRNG;
        LibPRNG.PRNG memory strategyRNG;
        LibPRNG.PRNG memory functionRNG;
        LibPRNG.PRNG memory argumentsRNG;

        vaultFuzzer.rand(actorRNG, functionRNG, argumentsRNG);
        strategyFuzzer.rand(functionRNG, strategyRNG, argumentsRNG);
        vaultFuzzer.rand(actorRNG, functionRNG, argumentsRNG);
        strategyFuzzer.rand(functionRNG, strategyRNG, argumentsRNG);
        vaultFuzzer.rand(actorRNG, functionRNG, argumentsRNG);
        strategyFuzzer.rand(functionRNG, strategyRNG, argumentsRNG);
    }
}
