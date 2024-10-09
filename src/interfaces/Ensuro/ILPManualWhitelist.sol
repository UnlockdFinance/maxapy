// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;


import {IPolicyPool} from "./IPolicyPool.sol";
import {ILPWhitelist} from "./ILPWhitelist.sol";
import {IEToken} from "./IEToken.sol";

interface ILPManualWhitelist is ILPWhitelist {
    enum WhitelistOptions {
        undefined,
        whitelisted,
        blacklisted
    }

    struct WhitelistStatus {
        WhitelistOptions deposit;
        WhitelistOptions withdraw;
        WhitelistOptions sendTransfer;
        WhitelistOptions receiveTransfer;
    }

    event LPWhitelistStatusChanged(address provider, WhitelistStatus whitelisted);

    function initialize(WhitelistStatus calldata defaultStatus) external;

    function whitelistAddress(address provider, WhitelistStatus calldata newStatus) external;

    function setWhitelistDefaults(WhitelistStatus calldata newStatus) external;

    function getWhitelistDefaults() external view returns (WhitelistStatus memory);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function LP_WHITELIST_ROLE() external view returns (bytes32);

    function LP_WHITELIST_ADMIN_ROLE() external view returns (bytes32);
}