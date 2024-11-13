# IStrategyVaultETH
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/interfaces/IStrategyVaultETH.sol)

**Inherits:**
[IStrategyVault](/src/interfaces/IStrategyVault.sol/interface.IStrategyVault.md), [IERC7535Upgradeable](/src/vault/ERC7535/IERC7535Upgradeable.sol/interface.IERC7535Upgradeable.md)


## Functions
### beaconChainAdmin

Get the address of the beacon chain admin


```solidity
function beaconChainAdmin() external view returns (address);
```

### initialize

Used to initialize the StrategyVaultETH given it's setup parameters.

*Called on construction by the StrategyVaultManager.*

*StrategyVaultETH so the deposit token is 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE*


```solidity
function initialize(
    uint256 _nftId,
    address _stratVaultCreator,
    bool _whitelistedDeposit,
    bool _upgradeable,
    address _oracle
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nftId`|`uint256`|The id of the ByzNft associated to this StrategyVault.|
|`_stratVaultCreator`|`address`|The address of the creator of the StrategyVault.|
|`_whitelistedDeposit`|`bool`|Whether the deposit function is whitelisted or not.|
|`_upgradeable`|`bool`|Whether the StrategyVault is upgradeable or not.|
|`_oracle`|`address`|The oracle implementation to use for the vault.|


### verifyWithdrawalCredentials

*Verify one or more validators (DV) have their withdrawal credentials pointed at this StrategyVault's EigenPod, and award
shares based on their effective balance. Proven validators are marked `ACTIVE` within the EigenPod, and
future checkpoint proofs will need to include them.*

*Withdrawal credential proofs MUST NOT be older than `currentCheckpointTimestamp`.*

*Validators proven via this method MUST NOT have an exit epoch set already (i.e MUST NOT have initiated an exit).*


```solidity
function verifyWithdrawalCredentials(
    uint64 beaconTimestamp,
    BeaconChainProofs.StateRootProof calldata stateRootProof,
    uint40[] calldata validatorIndices,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`beaconTimestamp`|`uint64`|the beacon chain timestamp sent to the 4788 oracle contract. Corresponds to the parent beacon block root against which the proof is verified. MUST be greater than `currentCheckpointTimestamp` and included in the last 8192 (~27 hours) Beacon Blocks.|
|`stateRootProof`|`BeaconChainProofs.StateRootProof`|proves a beacon state root against a beacon block root|
|`validatorIndices`|`uint40[]`|a list of validator indices being proven|
|`validatorFieldsProofs`|`bytes[]`|proofs of each validator's `validatorFields` against the beacon state root|
|`validatorFields`|`bytes32[][]`|the fields of the beacon chain "Validator" container. See consensus specs for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator|


### verifyCheckpointProofs

*Progress the current checkpoint towards completion by submitting one or more validator
checkpoint proofs. Anyone can call this method to submit proofs towards the current checkpoint.
For each validator proven, the current checkpoint's `proofsRemaining` decreases.*

*If the checkpoint's `proofsRemaining` reaches 0, the checkpoint is finalized.*

*This method can only be called when there is a currently-active checkpoint.*


```solidity
function verifyCheckpointProofs(
    BeaconChainProofs.BalanceContainerProof calldata balanceContainerProof,
    BeaconChainProofs.BalanceProof[] calldata proofs
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`balanceContainerProof`|`BeaconChainProofs.BalanceContainerProof`|proves the beacon's current balance container root against a checkpoint's `beaconBlockRoot`|
|`proofs`|`BeaconChainProofs.BalanceProof[]`|Proofs for one or more validator current balances against the `balanceContainerRoot`|


### verifyStaleBalance

*Prove that one of this vault's active validators was slashed on the beacon chain. A successful
staleness proof allows the caller to start a checkpoint.*


```solidity
function verifyStaleBalance(
    uint64 beaconTimestamp,
    BeaconChainProofs.StateRootProof calldata stateRootProof,
    BeaconChainProofs.ValidatorProof calldata proof
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`beaconTimestamp`|`uint64`|the beacon chain timestamp sent to the 4788 oracle contract. Corresponds to the parent beacon block root against which the proof is verified.|
|`stateRootProof`|`BeaconChainProofs.StateRootProof`|proves a beacon state root against a beacon block root|
|`proof`|`BeaconChainProofs.ValidatorProof`|the fields of the beacon chain "Validator" container, along with a merkle proof against the beacon state root. See the consensus specs for more details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator|


### activateCluster

Deposit 32ETH in the beacon chain to activate a Distributed Validator and start validating on the consensus layer.

*Function callable only by BeaconChainAdmin to be sure the deposit data are the ones of a DV created within the Byzantine protocol.*

*Reverts if not exactly 32 ETH are sent.*

*Reverts if the cluster is not in the vault.*


```solidity
function activateCluster(
    bytes calldata pubkey,
    bytes calldata signature,
    bytes32 depositDataRoot,
    bytes32 clusterId
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pubkey`|`bytes`|The 48 bytes public key of the beacon chain DV.|
|`signature`|`bytes`|The DV's signature of the deposit data.|
|`depositDataRoot`|`bytes32`|The root/hash of the deposit data for the DV's deposit.|
|`clusterId`|`bytes32`|The ID of the cluster associated to these deposit data.|


### startCheckpoint

*Create a checkpoint used to prove the vault's active validator set. Checkpoints are completed
by submitting one checkpoint proof per ACTIVE validator. During the checkpoint process, the total
change in ACTIVE validator balance is tracked, and any validators with 0 balance are marked `WITHDRAWN`.*

*Once finalized, the vault is awarded shares corresponding to:
- the total change in their ACTIVE validator balances
- any ETH in the pod not already awarded shares*

*A checkpoint cannot be created if the pod already has an outstanding checkpoint. If
this is the case, the pod owner, i.e the vault, MUST complete the existing checkpoint before starting a new one.*

*If waiting too long to submit your checkpoint proof, you may need to use a full archival beacon node to re-generate the proofs.
This is because the EIP-4788 oracle is valid for 27 hours, 8191 blocks.*


```solidity
function startCheckpoint(bool revertIfNoBalance) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revertIfNoBalance`|`bool`|Forces a revert if the pod ETH balance is 0. This allows the pod owner to prevent accidentally starting a checkpoint that will not increase their shares|


### getVaultDVNumber

Returns the number of active DVs staked by the Strategy Vault.


```solidity
function getVaultDVNumber() external view returns (uint256);
```

### getAllDVIds

Returns the IDs of the active DVs staked by the Strategy Vault.


```solidity
function getAllDVIds() external view returns (bytes32[] memory);
```

### createEigenPod

Create an EigenPod for the StrategyVault.

*Can only be called by the StrategyVaultManager during the vault creation.*


```solidity
function createEigenPod() external;
```

## Events
### ETHDeposited
Emitted when ETH is deposited into the Strategy Vault (either mint or deposit function)


```solidity
event ETHDeposited(address indexed receiver, uint256 assets, uint256 shares);
```

## Errors
### CanOnlyDepositMultipleOf32ETH
*Returned when trying to deposit an incorrect amount of ETH. Can only deposit a multiple of 32 ETH. (32, 64, 96, 128, etc.)*


```solidity
error CanOnlyDepositMultipleOf32ETH();
```

### OnlyBeaconChainAdmin
*Returned when trying to trigger Beacon Chain transactions from an unauthorized address*


```solidity
error OnlyBeaconChainAdmin();
```

### ClusterNotInVault
*Returned when trying to interact with a cluster ID not in the vault*


```solidity
error ClusterNotInVault();
```

