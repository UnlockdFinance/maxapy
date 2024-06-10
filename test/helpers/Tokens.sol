// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

contract Tokens {
    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////
    /// @notice mainnet tokens
    address public constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant ST_ETH_MAINNET = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant DAI_MAINNET = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant LUSD_MAINNET = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant USDT_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /// @notice polygon tokens
    address public constant USDT_POLYGON = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address public constant DAI_POLYGON = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address public constant USDCE_POLYGON = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    /// @notice token units
    uint256 public _1_USDC = 1e6;
    uint256 public _1_USDT = _1_USDC;
    uint256 public _1_DAI = 1 ether;

    /// @notice Getter function for tokens
    function getTokensList(string memory chain) public pure returns (address[] memory) {
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
}
