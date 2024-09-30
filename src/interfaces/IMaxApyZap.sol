// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {IMaxApyVault} from "src/interfaces/IMaxApyVault.sol";

interface IMaxApyZap {
  
    struct MaxInData {
        IMaxApyVault vault;
        uint256 amount;
        address recipient;
        uint256 minSharesOut;
        address router;
        address assetIn;
        bytes swapData;
    }

    struct MaxOutData {
        IMaxApyVault vault;
        uint256 shares;
        address recipient;
        uint256 minAmountOut;
        address router;
        address assetOut;
        bytes swapData;
    }

    function maxIn(MaxInData calldata data) external returns (uint256 sharesOut);
    
    function maxInWithPermit(MaxInData calldata data, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external returns (uint256 sharesOut);

    function maxInNative(MaxInData calldata data) external payable returns (uint256 sharesOut);

    function maxOut(MaxOutData calldata data) external returns (uint256 amountOut);

    function maxOutNative(MaxOutData calldata data) external returns (uint256 amountOut);
}
