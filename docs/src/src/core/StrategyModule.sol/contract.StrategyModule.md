# StrategyVault
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/80b6cda4622c51c2217311610eeb15b655b99e2c/src/core/StrategyVault.sol)

**Inherits:**
[IStrategyVault](/src/interfaces/IStrategyVault.sol/interface.IStrategyVault.md), Initializable


## State Variables
### FINALITY_TIME
Average time for block finality in the Beacon Chain


```solidity
uint16 internal constant FINALITY_TIME = 16 minutes;
```


### CLUSTER_SIZE

```solidity
uint8 internal constant CLUSTER_SIZE = 4;
```


### stratVaultManager
The single StrategyVaultManager for Byzantine


```solidity
IStrategyVaultManager public immutable stratVaultManager;
```


### byzNft
ByzNft contract


```solidity
IByzNft public immutable byzNft;
```


### auction
Address of the Auction contract


```solidity
IAuction public immutable auction;
```


### eigenPodManager
EigenLayer's EigenPodManager contract

*this is the pod manager transparent proxy*


```solidity
IEigenPodManager public immutable eigenPodManager;
```


### delegationManager
EigenLayer's DelegationManager contract


```solidity
IDelegationManager public immutable delegationManager;
```


### stratVaultNftId
The ByzNft associated to this StrategyVault.

The owner of the ByzNft is the StrategyVault owner.
TODO When non-upgradeable put that variable immutable and set it in the constructor


```solidity
uint256 public stratVaultNftId;
```


### clusterDetails

```solidity
ClusterDetails public clusterDetails;
```


## Functions
### onlyNftOwner


```solidity
modifier onlyNftOwner();
```

### onlyNftOwnerOrStratVaultManager


```solidity
modifier onlyNftOwnerOrStratVaultManager();
```

### onlyStratVaultManager


```solidity
modifier onlyStratVaultManager();
```

### constructor


```solidity
constructor(
    IStrategyVaultManager _stratVaultManager,
    IAuction _auction,
    IByzNft _byzNft,
    IEigenPodManager _eigenPodManager,
    IDelegationManager _delegationManager
);
```

### initialize

Used to initialize the nftId of that StrategyVault and its owner.

*Called on construction by the StrategyVaultManager.*


```solidity
function initialize(uint256 _nftId, address _initialOwner) external initializer;
```

### receive

Payable fallback function that receives ether deposited to the StrategyVault contract

*Strategy Vault is the address where to send the principal ethers post exit.*


```solidity
receive() external payable;
```

### stakeNativeETH

Deposit 32ETH in the beacon chain to activate a Distributed Validator and start validating on the consensus layer.
Also creates an EigenPod for the StrategyVault. The NFT owner can staker additional native ETH by calling again this function.

*Function is callable only by the StrategyVaultManager or the NFT Owner.*

*The first call to this function is done by the StrategyVaultManager and creates the StrategyVault's EigenPod.*


```solidity
function stakeNativeETH(
    bytes calldata pubkey,
    bytes calldata signature,
    bytes32 depositDataRoot
) external payable onlyNftOwnerOrStratVaultManager;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pubkey`|`bytes`|The 48 bytes public key of the beacon chain DV.|
|`signature`|`bytes`|The DV's signature of the deposit data.|
|`depositDataRoot`|`bytes32`|The root/hash of the deposit data for the DV's deposit.|


### callEigenPodManager

Call the EigenPodManager contract


```solidity
function callEigenPodManager(bytes calldata data) external payable onlyNftOwner returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`bytes`|to call contract|


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
) external onlyNftOwner;
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
function delegateTo(address operator) external onlyNftOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operator`|`address`|The account teh Strategy Vault is delegating its assets to for use in serving applications built on EigenLayer.|


### setClusterDetails

Set the `clusterDetails` struct of the StrategyVault.

*Callable only by the StrategyVaultManager and bound a pre-created DV to this StrategyVault.*


```solidity
function setClusterDetails(Node[4] calldata nodes, DVStatus dvStatus) external onlyStratVaultManager;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodes`|`Node[4]`|An array of Node making up the DV|
|`dvStatus`|`DVStatus`|The status of the DV, refer to the DVStatus enum for details.|


### stratVaultOwner

Returns the address of the owner of the Strategy Vault's ByzNft.


```solidity
function stratVaultOwner() public view returns (address);
```

### getDVStatus

Returns the status of the Distributed Validator (DV)


```solidity
function getDVStatus() public view returns (DVStatus);
```

### getDVNodesDetails

Returns the DV nodes details of the Strategy Vault
It returns the eth1Addr, the number of Validation Credit and the reputation score of each nodes.


```solidity
function getDVNodesDetails() public view returns (IStrategyVault.Node[4] memory);
```

### _executeCall

Execute a low level call


```solidity
function _executeCall(address payable to, uint256 value, bytes memory data) private returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address payable`|address to execute call|
|`value`|`uint256`|amount of ETH to send with call|
|`data`|`bytes`|bytes array to execute|


