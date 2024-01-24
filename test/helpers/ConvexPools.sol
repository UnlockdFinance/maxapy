// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

contract ConvexPools {
    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////
    /// @notice Booster
    address public constant CONVEX_BOOSTER_MAINNET = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /// @notice Curve Pools

    /// @notice Price Oracle Curve Pools
    address public constant DETH_FRXETH_CURVE_POOL = 0x7C0d189E1FecB124487226dCbA3748bD758F98E4;
    address public constant SWETH_FRXETH_CURVE_POOL = 0x67e0bDbe0A2C5999A60D048f50e794218056b767;
    address public constant MSETH_FRXETH_CURVE_POOL = 0x2d600BbBcC3F1B6Cb9910A70BaB59eC9d5F81B9A;
    address public constant RETH_FRXETH_CURVE_POOL = 0xe7c6E0A739021CdbA7aAC21b4B728779EeF974D9;
    address public constant CBETH_FRXETH_CURVE_POOL = 0x73069892f6750CCaaAbabaDC54b6b6b36B3A057D;
    address public constant ETH_RETH_CURVE_POOL = 0x0f3159811670c117c372428D4E69AC32325e4D0F;
    address public constant ETH_CBETH_CURVE_POOL = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
    address public constant ETH_OETH_CURVE_POOL = 0x94B17476A93b3262d87B9a326965D1E91f9c13E7;
    address public constant ETH_FRXETH_CURVE_POOL = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
    address public constant ETH_STETH_CURVE_POOL_V2 = 0x21E27a5E5513D6e65C4f830167390997aA84843a;
    address public constant ETH_WBETH_CURVE_POOL = 0xBfAb6FA95E0091ed66058ad493189D2cB29385E6;

    /// @notice Pools without oracle
    address public constant ETH_MSETH_CURVE_POOL = 0xc897b98272AA23714464Ea2A0Bd5180f1B8C0025;
    address public constant ETH_PETH_CURVE_POOL = 0x9848482da3Ee3076165ce6497eDA906E66bB85C5;
    address public constant ETH_ALETH_CURVE_POOL = 0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e;
    address public constant ALETH_FRXETH_CURVE_POOL = 0xB657B895B265C38c53FFF00166cF7F6A3C70587d;
    address public constant STETH_FRXETH_CURVE_POOL = 0x4d9f9D15101EEC665F77210cB999639f760F831E;
    address public constant RETH_WSTETH_CURVE_POOL = 0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08;
    address public constant ETH_STETH_CURVE_POOL_V1 = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant ETH_SETH_CURVE_POOL = 0xc5424B857f758E906013F3555Dad202e4bdB4567;

    /// Tokens
    address public constant CRV_WETH_CURVE_POOL = 0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
    address public constant CVX_WETH_CURVE_POOL = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;

    /// @notice Convex Pool IDs
    uint256 public constant ETH_STETH_CONVEX_POOL_ID = 177;
    uint256 public constant DETH_FRXETH_CONVEX_POOL_ID = 195;
}
