# StrategyModule
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/039f6bfc2d98b2c720b4f881f44b17511a859648/src/core/StrategyModule.sol)

**Inherits:**
[IStrategyModule](/src/interfaces/IStrategyModule.sol/interface.IStrategyModule.md), Initializable


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


### stratModManager
The single StrategyModuleManager for Byzantine


```solidity
IStrategyModuleManager public immutable stratModManager;
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


### stratModNftId
The ByzNft associated to this StrategyModule.

The owner of the ByzNft is the StrategyModule owner.


```solidity
uint256 public stratModNftId;
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

### onlyStratModOwnerOrManager


```solidity
modifier onlyStratModOwnerOrManager();
```

### onlyStratModOwnerOrDVManager


```solidity
modifier onlyStratModOwnerOrDVManager();
```

### onlyAuctionContract


```solidity
modifier onlyAuctionContract();
```

### constructor


```solidity
constructor(
    IStrategyModuleManager _stratModManager,
    IAuction _auction,
    IByzNft _byzNft,
    IEigenPodManager _eigenPodManager,
    IDelegationManager _delegationManager
);
```

### initialize

Used to initialize the  nftId of that StrategyModule.

*Called on construction by the StrategyModuleManager.*


```solidity
function initialize(uint256 _nftId) external initializer;
```

### receive

Payable fallback function that receives ether deposited to the StrategyModule contract

*Used by the StrategyModuleManager to send the staker's deposited ETH while waiting for the DV creation.*

*Strategy Module is the address where to send the principal ethers post exit.*


```solidity
receive() external payable;
```

### createPod

Creates an EigenPod for the strategy module.

*Function will revert if not called by the StrategyModule owner or StrategyModuleManager.*

*Function will revert if the StrategyModule already has an EigenPod.*

*Returns EigenPod address*


```solidity
function createPod() external onlyStratModOwnerOrManager returns (address);
```

### beaconChainDeposit

Deposit 32ETH from the contract's balance in the beacon chain to activate a Distributed Validator.

*Function is callable only by the StrategyModule owner or the cluster manager => Byzantine is non-custodian*

*Byzantine or Strategy Module owner must first initialize the trusted pubkey of the DV.*


```solidity
function beaconChainDeposit(
    bytes calldata pubkey,
    bytes calldata signature,
    bytes32 depositDataRoot
) external onlyStratModOwnerOrDVManager;
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
the stratModOwner are pointed to the EigenPod of this contract. It also verifies the effective balance of the DV.
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

The caller delegate its Strategy Module's stake to an Eigen Layer operator.

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
|`operator`|`address`|The account teh STrategy Module is delegating its assets to for use in serving applications built on EigenLayer.|


### updateClusterDetails

Edit the `clusterDetails` struct once the auction is over

*Callable only by the AuctionContract. Should be called once an auction is over and `CLUSTER_SIZE` validators have been selected.*

*Reverts if the `nodes` array is not of length `CLUSTER_SIZE`.*


```solidity
function updateClusterDetails(Node[] calldata nodes, address clusterManager) external onlyAuctionContract;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodes`|`Node[]`|An array of Node making up the DV (the first `CLUSTER_SIZE` winners of the auction)|
|`clusterManager`|`address`|The node responsible for handling the DKG and deposit the 32ETH in the Beacon Chain (more rewards to earn)|


### setTrustedDVPubKey

StrategyModuleManager or Owner fill the expected/ trusted public key for its DV (retrievable from the Obol SDK/API).

*Protection against a trustless cluster manager trying to deposit the 32ETH in another ethereum validator (in `beaconChainDeposit`)*

*Revert if the pubkey is not 48 bytes long.*

*Revert if not callable by StrategyModuleManager or StrategyModule owner.*


```solidity
function setTrustedDVPubKey(bytes calldata trustedPubKey) external onlyStratModOwnerOrManager;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`trustedPubKey`|`bytes`|The public key of the DV retrieved with the Obol SDK/API from the configHash|


### withdrawContractBalance

Allow the Strategy Module's owner to withdraw the smart contract's balance.

*Revert if the caller is not the owner of the Strategy Module's ByzNft.*


```solidity
function withdrawContractBalance() external onlyNftOwner;
```

### stratModOwner

Returns the address of the owner of the Strategy Module's ByzNft.


```solidity
function stratModOwner() public view returns (address);
```

### getTrustedDVPubKey

Returns the DV's public key set by a trusted party


```solidity
function getTrustedDVPubKey() public view returns (bytes memory);
```

### getDVStatus

Returns the status of the Distributed Validator (DV)


```solidity
function getDVStatus() public view returns (DVStatus);
```

### getClusterManager

Returns the DV's cluster manager


```solidity
function getClusterManager() public view returns (address);
```

### getDVNodesAddr

Returns the DV's nodes' eth1 addresses


```solidity
function getDVNodesAddr() public view returns (address[] memory);
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


### _isValidPubKey

Verify the public key provided by cluster Manager before depositing the ETH.


```solidity
function _isValidPubKey(bytes memory trustedPubKey, bytes memory untrustedPubKey) private pure returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`trustedPubKey`|`bytes`|The public key verified by Byzantine or the Strategy Module owner.|
|`untrustedPubKey`|`bytes`|The public key provided by the cluster Manager when depositing the ETH.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|true if the public keys match, false otherwise.|


