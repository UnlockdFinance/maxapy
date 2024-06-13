// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { MaxApyVault } from "./MaxApyVault.sol";
import { CREATE3 } from "solady/utils/CREATE3.sol";
import { LibString } from "solady/utils/LibString.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { MatadataReaderLib } from "solady/utils/MetadataReaderLib.sol";

contract VaultFactory is OwnableRoles {
    using LibString for string;
    using MetadataReaderLib for address;
    ////////////////////////////////////////////////////////////////
    ///                         CONSTANTS                        ///
    ////////////////////////////////////////////////////////////////
    /// Roles
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant DEPLOYER_ROLE = _ROLE_1;
    /// Vault creation code
    bytes immutable cachedCreationCode;
    /// MaxApy treasury
    address public immutable treasury;

    constructor(address _treasury) {
        /// We cache the vault creation code into storage
        cachedCreationCode = type(MaxApyVault).creationCode;
        treasury = _treasury;
    }

    ////////////////////////////////////////////////////////////////
    ///                         DEPLOYMENT                       ///
    ////////////////////////////////////////////////////////////////
    /// @notice Deploys a vault with a deterministic address
    /// @param underlyingAsset address of the ERC20 deposit token of the vault
    /// @param salt seed hash to compute the new address from
    function deploy(address underlyingAsset, bytes32 salt) external onlyRoles(DEPLOYER_ROLE) {
        string memory symbol = underlyingAsset.readSymbol();
        CREATE3.deploy(
            salt,
            abi.encodePacked(
                cachedCreationCode,
                abi.encode(underlyingAsset, "MaxApy-".concat(symbol).concat(" Vault"), "max".concat(symbol), treasury),
                0
            )
        );
    }

    ////////////////////////////////////////////////////////////////
    ///                    EXTERNAL VIEW FUNCTIONS               ///
    ////////////////////////////////////////////////////////////////
    /// @notice Computes the deterministic deployment address of a vault given a salt
    /// @param salt the deployment salt
    function computeAddress(bytes32 salt) external view returns (address) {
        return getDeployed(salt);
    }
}
