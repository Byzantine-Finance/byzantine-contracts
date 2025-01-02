// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Checkpoints} from "lib/symbiotic-core/lib/openzeppelin-contracts/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IVault} from "@symbioticfi/core/src/interfaces/vault/IVault.sol";
import {IVaultStorage} from "@symbioticfi/core/src/interfaces/vault/IVaultStorage.sol";
import {IBaseDelegator} from "@symbioticfi/core/src/interfaces/delegator/IBaseDelegator.sol";
import {IEntity} from "@symbioticfi/core/src/interfaces/common/IEntity.sol";
import {IRegistry} from "@symbioticfi/core/src/interfaces/common/IRegistry.sol";
import {Subnetwork} from "@symbioticfi/core/src/contracts/libraries/Subnetwork.sol";
import {ISlasher} from "@symbioticfi/core/src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "@symbioticfi/core/src/interfaces/slasher/IVetoSlasher.sol";


contract NetworkMiddlewareMock {
    using Checkpoints for Checkpoints.Trace224;
    Checkpoints.Trace224 private _checkpoints;

    /// @notice The only subnetwork ID for mev-commit middleware. Ie. mev-commit doesn't implement multiple subnets.
    uint96 internal constant _SUBNETWORK_ID = 1;

    /// @notice Enum TYPE for Symbiotic core NetworkRestakeDelegator.
    uint64 internal constant _NETWORK_RESTAKE_DELEGATOR_TYPE = 0;

    /// @notice Enum TYPE for Symbiotic core FullRestakeDelegator.
    uint64 internal constant _FULL_RESTAKE_DELEGATOR_TYPE = 1;

    /// @notice Enum TYPE for Symbiotic core InstantSlasher.
    uint64 internal constant _INSTANT_SLASHER_TYPE = 0;

    /// @notice Enum TYPE for Symbiotic core VetoSlasher.
    uint64 internal constant _VETO_SLASHER_TYPE = 1;

    /// @notice Symbiotic core network registry.
    IRegistry public networkRegistry;

    /// @notice Symbiotic core operator registry.
    IRegistry public operatorRegistry;

    /// @notice Symbiotic core vault factory.
    IRegistry public vaultFactory;

    /// @notice The network address, which must have registered with the NETWORK_REGISTRY.
    address public network;

    /// @notice The owner of the network middleware.
    address public owner;

    /// @notice Information about a vault
    struct VaultInfo {
        bool exists;
        /// @notice The slash amount per validator, relevant to this vault.
        Checkpoints.Trace224 slashAmountHistory;
    }

    /// @notice Information about an operator
    struct OperatorInfo {
        bool exists;
    }

    /// @notice Information about a slash
    struct SlashInfo {
        bool exists;
        uint256 amount;
        uint256 captureTimestamp;
    }

    /// @notice Mapping of vaults to their information
    mapping(address => VaultInfo) private _vaults;

    /// @notice Mapping of operators to their information
    mapping(address => OperatorInfo) private _operators;

    /// @notice Mapping of vaults to operators to their slashes
    mapping(address => mapping(address => SlashInfo)) private _slashes;

    constructor(        
        IRegistry _networkRegistry,
        IRegistry _operatorRegistry,
        address _network,
        address _owner) {
        network = _network;
        networkRegistry = _networkRegistry;
        operatorRegistry = _operatorRegistry;
        owner = _owner;
    }

    // /// @notice Registers a vault
    // /// @param vault The address of the vault
    // /// @param slashAmount The initial slash amount
    // function registerVault(address vault, uint224 slashAmount) external {
    //     _vaults[vault] = VaultInfo({
    //         exists: true,
    //         slashAmountHistory: Checkpoints.Trace224(new Checkpoints.Checkpoint224[](0))
    //     });
    //     _vaults[vault].slashAmountHistory.push(SafeCast.toUint32(block.timestamp), slashAmount);
    // }

    // /// @notice Unregisters a vault
    // /// @param vault The address of the vault
    // function unregisterVault(address vault) external {
    //     require(_vaults[vault].exists, "Vault not registered");
    //     delete _vaults[vault];
    // }

    // /// @notice Registers an operator
    // /// @param operator The address of the operator
    // function registerOperator(address operator) external {
    //     _operators[operator].exists = true;
    // }

    // /// @notice Unregisters an operator
    // /// @param operator The address of the operator
    // function unregisterOperator(address operator) external {
    //     require(_operators[operator].exists, "Operator not registered");
    //     delete _operators[operator];
    // }

    // /// @notice Slashes an operator
    // /// @param vault The address of the vault
    // /// @param operator The address of the operator
    // /// @param capturedAt The timestamp of the slash
    // function slashOperator(address vault, address operator, uint256 capturedAt) external {
    //     require(_vaults[vault].exists, "Vault not registered");
    //     require(_operators[operator].exists, "Operator not registered");
    //     require(!_slashes[vault][operator].exists, "Slash already registered");

    //     // Slash amount is enforced as non-zero in _registerVault.
    //     uint160 amount = _getSlashAmountAt(vault, capturedAt);
    //     _slashes[vault][operator] = SlashInfo({exists: true, amount: amount, captureTimestamp: capturedAt});

    //     address slasher = IVault(vault).slasher();
    //     uint256 slasherType = IEntity(slasher).TYPE();
    //     uint256 slashedAmount;
    //     if (slasherType == _VETO_SLASHER_TYPE) {
    //         IVetoSlasher vetoSlasher = IVetoSlasher(slasher);
    //         uint256 slashIndex = vetoSlasher.requestSlash(
    //             _getSubnetwork(), operator, amount, SafeCast.toUint48(capturedAt), new bytes(0));
    //         // Since resolver = address(0), slash can be executed immediately.
    //         slashedAmount = vetoSlasher.executeSlash(slashIndex, new bytes(0));
    //     } else if (slasherType == _INSTANT_SLASHER_TYPE) {
    //         slashedAmount = ISlasher(slasher).slash(
    //             _getSubnetwork(), operator, amount, SafeCast.toUint48(capturedAt), new bytes(0));
    //     }
    // }

    // function _getSlashAmountAt(address vault, uint256 timestamp) internal view returns (uint160 amount) {
    //     require(timestamp <= block.timestamp, "Future timestamp disallowed");
    //     VaultInfo storage record = _vaults[vault];
    //     require(record.exists, "Vault not registered");
    //     uint224 lookupAmount = record.slashAmountHistory.upperLookup(SafeCast.toUint32(timestamp));
    //     require(lookupAmount != 0, "No slash amount at timestamp");
    //     return uint160(lookupAmount);
    // }

    // function _getSubnetwork() internal view returns (bytes32) {
    //     return Subnetwork.subnetwork(network, _SUBNETWORK_ID);
    // }

}