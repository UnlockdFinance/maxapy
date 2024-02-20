// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {MaxApyVaultV2} from "src/MaxApyVaultV2.sol";
import {IMaxApyVaultV2} from "src/interfaces/IMaxApyVaultV2.sol";
import {ERC20, IERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {ERC4626} from "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {YearnWETHStrategy, IYVault} from "src/strategies/WETH/yearn/YearnWETHStrategy.sol";
import {SommelierTurboStEthStrategy, ICellar} from "src/strategies/WETH/sommelier/SommelierTurboStEthStrategy.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";


/**
  Mock WETH deployed at address: 0x5E8Ab96a3f4d04e13540A4D59cbf9fae363a0A48
  MaxApy Vault deployed at address: 0xb5b34A401eD83308173133160aF167A92BC3DFD9
  Mock yVault deployed at address: 0xC4E34914009eceD65e86085eb7Bbe3E169d61bdC
  Yearn WETH Strategy Deployed at address:  0xf49571488DF92996192aca393603fFBcd7650416
  Fake Sommelier Cellar deployed at address: 0xD63ba36Ba785E7acD90fa74a131f806cf00c16A6
  Sommelier TurboStEth Strategy Deployed at address:  0x13b14403c2f57E36F2FFaCAa81263D40bD88cE5B

 */

contract MockERC20 is ERC20 {
    constructor() ERC20("Wrapped Eth", "WETH"){}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MockYearnVault is ERC20 {
    using SafeTransferLib for address;

    uint256 public constant DEGRADATION_COEFFICIENT = 1e18;

    address public immutable underlyingAsset;
    uint256 public lockedProfit;
    uint256 public lockedProfitDegradation=0;

    constructor(address _underlyingAsset) ERC20("MockYearnVault", "MYV") {
        underlyingAsset = _underlyingAsset;
    }
    
    function deposit(uint256 amount) external returns (uint256) {
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        return amount;
    }

    function withdraw(uint256 amount) external returns (uint256) {
        _burn(msg.sender, amount);
        underlyingAsset.safeTransfer(msg.sender, amount * 98 / 100);
        return amount;
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function pricePerShare() external view returns (uint256) {
        return totalAssets() * 1e18 / totalSupply();
    }

    function token() external view returns (address) {
        return address(underlyingAsset);
    }

    function totalAssets() public view returns (uint256) {
        return balanceOf(address(this));
    }

    function lastReport() external view returns (uint256) {
        return block.timestamp - 10000 days;
    }

}

contract MockSommelierCellar is ERC4626 {
    function totalAssetsWithdrawable() external view returns (uint256 assets){
        return totalAssets();
    }

    function isShutdown() external pure returns (bool){
        return false;
    }

    function isPaused() external pure returns (bool){
        return false;
    }

    constructor(address _underlyingAsset) ERC4626(IERC20(_underlyingAsset)) ERC20("Mock Sommelier Cellar", "MSC") {}
}

contract DeployProtocolTestnetScript is Script {
    ////////////////////////////////////////////////////////////////
    ///                      CONSTANTS                           ///
    ////////////////////////////////////////////////////////////////
    address public constant TREASURY = 0xCb1D84fC7925D564414bd9f81E921aA3847b58fE;

    function run() public {
        address [] memory keepers = new address[](3);
        keepers[0] = (0xe4a72bec8d2f18F7b9D4B3c5b2571B087F682BcE);
        keepers[1] = (0xfB09A9175c4D3b941236ad98Aeba200b8Dfd8182);
        keepers[2] = (0xCb1D84fC7925D564414bd9f81E921aA3847b58fE);
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockERC20 token = new MockERC20();

        token.mint(0xfB09A9175c4D3b941236ad98Aeba200b8Dfd8182, 10000 * 10 ** 18);

        console.log("Mock WETH deployed at address:", address(token));

        MaxApyVaultV2 maxApyVaultV2 = new MaxApyVaultV2(address(token), "MaxApyWETHVault", "maxWETH", TREASURY);

        console.log("MaxApy Vault deployed at address:", address(maxApyVaultV2));

        MockYearnVault yVault = new MockYearnVault(address(token));

        console.log("Mock yVault deployed at address:", address(yVault));

        YearnWETHStrategy yStrategy = new YearnWETHStrategy();

        yStrategy.initialize(
            IMaxApyVaultV2(address(maxApyVaultV2)), keepers, "Yearn WETH", 0xCb1D84fC7925D564414bd9f81E921aA3847b58fE, IYVault(address(yVault))
        );

        yStrategy.transferOwnership(0xfB09A9175c4D3b941236ad98Aeba200b8Dfd8182);

        console.log("Yearn WETH Strategy Deployed at address: ", address(yStrategy));

        MockSommelierCellar cellar = new MockSommelierCellar(address(token));

        console.log("Fake Sommelier Cellar deployed at address:", address(cellar));

        SommelierTurboStEthStrategy sStrategy = new SommelierTurboStEthStrategy();

        sStrategy.initialize(
            IMaxApyVaultV2(address(maxApyVaultV2)), keepers, "Sommelier Turbo StETh", 0xCb1D84fC7925D564414bd9f81E921aA3847b58fE, ICellar(address(cellar))
        );

        sStrategy.transferOwnership(0xfB09A9175c4D3b941236ad98Aeba200b8Dfd8182);

        console.log("Sommelier TurboStEth Strategy Deployed at address: ", address(sStrategy));
       
        maxApyVaultV2.grantRoles(0xe4a72bec8d2f18F7b9D4B3c5b2571B087F682BcE, 1 << 0);
        maxApyVaultV2.grantRoles(0xfB09A9175c4D3b941236ad98Aeba200b8Dfd8182, 1 << 0);
        maxApyVaultV2.transferOwnership(0xfB09A9175c4D3b941236ad98Aeba200b8Dfd8182);

        maxApyVaultV2.addStrategy(address(yStrategy), 4000, type(uint256).max, 0, 200);
        maxApyVaultV2.addStrategy(address(sStrategy), 5000, type(uint256).max, 0, 400);

        vm.stopBroadcast();
    }
}