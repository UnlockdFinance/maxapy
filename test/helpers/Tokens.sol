// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

address constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
address constant ST_ETH_MAINNET = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
address constant DAI_MAINNET = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
address constant LUSD_MAINNET = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
address constant USDT_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
address constant CRV_MAINNET = 0xD533a949740bb3306d119CC777fa900bA034cd52;
address constant CVX_MAINNET = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
address constant FRXETH_MAINNET = 0x5E8422345238F34275888049021821E8E08CAa1f;

address constant USDT_POLYGON = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
address constant DAI_POLYGON = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
address constant USDCE_POLYGON = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

uint256 constant _1_USDC = 1e6;
uint256 constant _1_USDT = _1_USDC;
uint256 constant _1_DAI = 1 ether;

function getTokensList(string memory chain) pure returns (address[] memory) {
    if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("MAINNET"))) {
        address[] memory tokens = new address[](5);
        tokens[0] = WETH_MAINNET;
        tokens[1] = USDC_MAINNET;
        tokens[2] = DAI_MAINNET;
        tokens[3] = LUSD_MAINNET;
        tokens[4] = USDT_MAINNET;
        return tokens;
    } else if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("POLYGON"))) {
        address[] memory tokens = new address[](3);
        tokens[0] = USDT_POLYGON;
        tokens[1] = DAI_POLYGON;
        tokens[2] = USDCE_POLYGON;
        return tokens;
    } else {
        revert("InvalidChain");
    }
}
