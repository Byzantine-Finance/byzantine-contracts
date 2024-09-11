# IStrategyVault
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/80b6cda4622c51c2217311610eeb15b655b99e2c/src/interfaces/IStrategyVault.sol)


## Functions
### initialize

Used to initialize the nftId of that StrategyVault and its owner.

*Called on construction by the StrategyVaultManager.*


```solidity
function initialize(uint256 _nftId, address _initialOwner) external;
```

### stratVaultNftId

Returns the owner of this StrategyVault


```solidity
function stratVaultNftId() external view returns (uint256);
```

### stratVaultOwner

Returns the address of the owner of the Strategy Vault's ByzNft.


```solidity
function stratVaultOwner() external view returns (address);
```

### stakeNativeETH

Deposit 32ETH in the beacon chain to activate a Distributed Validator and start validating on the consensus layer.
Also creates an EigenPod for the StrategyVault. The NFT owner can staker additional native ETH by calling again this function.

*Function is callable only by the StrategyVaultManager or the NFT Owner.*

*The first call to this function is done by the StrategyVaultManager and creates the StrategyVault's EigenPod.*


```solidity
function stakeNativeETH(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pubkey`|`bytes`|The 48 bytes public key of the beacon chain DV.|
|`signature`|`bytes`|The DV's signature of the deposit data.|
|`depositDataRoot`|`bytes32`|The root/hash of the deposit data for the DV's deposit.|


### verifyWithdrawalCredentials

This function verifies that the withdrawal credentials of the Distributed Validator(s) owned by
the stratVaultOwner are pointed to the EigenPod of this contract. It also verifies the effective balance of the DV.
It verifies the provided proof of the ETH DV against the beacon chain state root, marks the validator as 'active'
in EigenLayer, and credits the restaked ETH in Eigenlayer.

*That function must be called for a validator which is "INACTIVE".*

*The timestamp used to generate the Beacon Block Root is `block.timestamp - FINALITY_TIME` to be sure
that the Beacon Block is finalized.*

*The arguments can be generated with the Byzantine API.*

*/!\ The Withdrawal credential proof must be recent enough to be valid (no older than VERIFY_BALANCE_UPDATE_WINDOW_SECONDS).
It entails to re-generate a proof every 4.5 hours.*


```solidity
function verifyWithdrawalCredentials(
    uint64 proofTimestamp,
    BeaconChainProofs.StateRootProof calldata stateRootProof,
    uint40[] calldata validatorIndices,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proofTimestamp`|`uint64`|is the exact timestamp where the proof was generated|
|`stateRootProof`|`BeaconChainProofs.StateRootProof`|proves a `beaconStateRoot` against a block root fetched from the oracle|
|`validatorIndices`|`uint40[]`|is the list of indices of the validators being proven, refer to consensus specs|
|`validatorFieldsProofs`|`bytes[]`|proofs against the `beaconStateRoot` for each validator in `validatorFields`|
|`validatorFields`|`bytes32[][]`|are the fields of the "Validator Container", refer to consensus specs for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator|


### verifyBalanceUpdates

This function records an update (either increase or decrease) in a validator's balance which is active,
(which has already called `verifyWithdrawalCredentials`).

*That function must be called for a validator which is "ACTIVE".*

*The timestamp used to generate the Beacon Block Root is `block.timestamp - FINALITY_TIME` to be sure
that the Beacon Block is finalized.*

*The arguments can be generated with the Byzantine API.*

*/!\ The Withdrawal credential proof must be recent enough to be valid (no older than VERIFY_BALANCE_UPDATE_WINDOW_SECONDS).
It entails to re-generate a proof every 4.5 hours.*


```solidity
function verifyBalanceUpdates(
    uint64 proofTimestamp,
    BeaconChainProofs.StateRootProof calldata stateRootProof,
    uint40[] calldata validatorIndices,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proofTimestamp`|`uint64`|is the exact timestamp where the proof was generated|
|`stateRootProof`|`BeaconChainProofs.StateRootProof`|proves a `beaconStateRoot` against a block root fetched from the oracle|
|`validatorIndices`|`uint40[]`|is the list of indices of the validators being proven, refer to consensus specs|
|`validatorFieldsProofs`|`bytes[]`|proofs against the `beaconStateRoot` for each validator in `validatorFields`|
|`validatorFields`|`bytes32[][]`|are the fields of the "Validator Container", refer to consensus specs: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator|


### delegateTo

The caller delegate its Strategy Vault's stake to an Eigen Layer operator.

/!\ Delegation is all-or-nothing: when a Staker delegates to an Operator, they delegate ALL their stake.

*The operator must not have set a delegation approver, everyone can delegate to it without permission.*

*Ensures that:
1) the `staker` is not already delegated to an operator
2) the `operator` has indeed registered as an operator in EigenLayer*


```solidity
function delegateTo(address operator) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operator`|`address`|The account teh Strategy Vault is delegating its assets to for use in serving applications built on EigenLayer.|


### setClusterDetails

Set the `clusterDetails` struct of the StrategyVault.

*Callable only by the StrategyVaultManager and bound a pre-created DV to this StrategyVault.*


```solidity
function setClusterDetails(Node[4] calldata nodes, DVStatus dvStatus) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodes`|`Node[4]`|An array of Node making up the DV|
|`dvStatus`|`DVStatus`|The status of the DV, refer to the DVStatus enum for details.|

### callEigenPodManager

Call the EigenPodManager contract


```solidity
function callEigenPodManager(bytes calldata data) external payable returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`bytes`|to call contract|


### getDVStatus

Returns the status of the Distributed Validator (DV)


```solidity
function getDVStatus() external view returns (DVStatus);
```

### getDVNodesDetails

Returns the DV nodes details of the Strategy Vault
It returns the eth1Addr, the number of Validation Credit and the reputation score of each nodes.


```solidity
function getDVNodesDetails() external view returns (IStrategyVault.Node[4] memory);
```

## Errors
### OnlyNftOwner
*Error when unauthorized call to a function callable only by the Strategy Vault Owner (aka the ByzNft holder).*


```solidity
error OnlyNftOwner();
```

### OnlyNftOwnerOrStrategyVaultManager
*Error when unauthorized call to a function callable only by the StrategyVaultOwner or the StrategyVaultManager.*


```solidity
error OnlyNftOwnerOrStrategyVaultManager();
```

### OnlyStrategyVaultManager
*Error when unauthorized call to a function callable only by the StrategyVaultManager.*


```solidity
error OnlyStrategyVaultManager();
```

### InvalidClusterSize
*Returned when not privided the right number of nodes*


```solidity
error InvalidClusterSize();
```

### CallFailed
*Returned on failed Eigen Layer contracts call*


```solidity
error CallFailed(bytes data);
```

## Structs
### Node
Struct to store the details of a DV node registered on Byzantine


```solidity
struct Node {
    uint256 vcNumber;
    uint128 reputation;
    address eth1Addr;
}
```

### ClusterDetails
Struct to store the details of a Distributed Validator created on Byzantine


```solidity
struct ClusterDetails {
    DVStatus dvStatus;
    Node[4] nodes;
}
```

## Enums
### DVStatus

```solidity
enum DVStatus {
    WAITING_ACTIVATION,
    DEPOSITED_NOT_VERIFIED,
    ACTIVE_AND_VERIFIED,
    EXITED
}
```

