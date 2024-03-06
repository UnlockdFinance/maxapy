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

    /// @notice polygon tokens
    address public constant USDC_POLYGON = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    /// @notice Getter function for tokens 
    function getTokensList(string memory chain) public pure returns(address[] memory) {
        if(keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("MAINNET"))){
            address[] memory tokens = new address[](2);
            tokens[0] = WETH_MAINNET;
            tokens[1] = USDC_MAINNET;
            return tokens;
        }
        else if(keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("POLYGON"))){
            address[] memory tokens = new address[](1);
            tokens[0] = USDC_POLYGON;
            return tokens;
        }
        else revert("InvalidChain");
    }   
}
