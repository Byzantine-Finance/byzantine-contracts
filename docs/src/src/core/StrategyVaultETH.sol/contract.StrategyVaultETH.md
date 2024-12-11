# StrategyVaultETH
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/core/StrategyVaultETH.sol)

**Inherits:**
[StrategyVaultETHStorage](/src/core/StrategyVaultETHStorage.sol/abstract.StrategyVaultETHStorage.md), [ERC7535MultiRewardVault](/src/vault/ERC7535MultiRewardVault.sol/contract.ERC7535MultiRewardVault.md)


## Functions
### onlyNftOwner


```solidity
modifier onlyNftOwner();
```

### onlyStratVaultManager


```solidity
modifier onlyStratVaultManager();
```

### onlyBeaconChainAdmin


```solidity
modifier onlyBeaconChainAdmin();
```

### checkWhitelist


```solidity
modifier checkWhitelist();
```

### checkDelegator


```solidity
modifier checkDelegator();
```

### constructor


```solidity
constructor(
    IStrategyVaultManager _stratVaultManager,
    IAuction _auction,
    IByzNft _byzNft,
    IEigenPodManager _eigenPodManager,
    IDelegationManager _delegationManager,
    IStakerRewards _stakerRewards,
    address _beaconChainAdmin
);
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
) external override initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nftId`|`uint256`|The id of the ByzNft associated to this StrategyVault.|
|`_stratVaultCreator`|`address`|The address of the creator of the StrategyVault.|
|`_whitelistedDeposit`|`bool`|Whether the deposit function is whitelisted or not.|
|`_upgradeable`|`bool`|Whether the StrategyVault is upgradeable or not.|
|`_oracle`|`address`|The oracle implementation to use for the vault.|


### __StrategyVaultETH_init_unchained


```solidity
function __StrategyVaultETH_init_unchained(
    uint256 _nftId,
    address _stratVaultCreator,
    bool _whitelistedDeposit,
    bool _upgradeable
) internal onlyInitializing;
```

### receive

Payable fallback function that receives ether deposited to the StrategyVault contract

*Strategy Vault is the address where to send the principal ethers post exit.*


```solidity
receive() external payable override;
```

### deposit

Deposit ETH to the StrategyVault and get Vault shares in return. ERC7535 compliant.

*If whitelistedDeposit is true, then only users within the whitelist can call this function.*

*Revert if the amount deposited is not a multiple of 32 ETH.*

*Trigger auction(s) for each bundle of 32 ETH deposited to get Distributed Validator(s)*


```solidity
function deposit(
    uint256 assets,
    address receiver
) public payable override(ERC7535MultiRewardVault, IERC7535Upgradeable) checkWhitelist returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of ETH being deposit.|
|`receiver`|`address`|The address to receive the Byzantine vault shares.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of shares minted.|


### mint

Deposit ETH to the StrategyVault. Amount determined by number of shares minting. ERC7535 compliant.

*If whitelistedDeposit is true, then only users within the whitelist can call this function.*

*Revert if the amount deposited is not a multiple of 32 ETH.*

*Trigger auction(s) for each bundle of 32 ETH deposited to get Distributed Validator(s)*


```solidity
function mint(
    uint256 shares,
    address receiver
) public payable override(ERC7535MultiRewardVault, IERC7535Upgradeable) checkWhitelist returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of vault shares to mint.|
|`receiver`|`address`|The address to receive the Byzantine vault shares.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of ETH deposited.|


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


### startWithdrawETH

Begins the withdrawal process to pull ETH out of the StrategyVault

*Withdrawal is not instant - a withdrawal delay exists for removing the assets from EigenLayer*


```solidity
function startWithdrawETH(
    IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams,
    IStrategy[] memory strategies
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`queuedWithdrawalParams`|`IDelegationManager.QueuedWithdrawalParams[]`|TODO: Fill in|
|`strategies`|`IStrategy[]`|An array of strategy contracts for all tokens being withdrawn from EigenLayer.|


### delegateTo

Finalizes the withdrawal of ETH from the StrategyVault

The caller delegate its Strategy Vault's stake to an Eigen Layer operator.

/!\ Delegation is all-or-nothing: when a Staker delegates to an Operator, they delegate ALL their stake.

*Can only be called after the withdrawal delay is finished*

*The operator must not have set a delegation approver, everyone can delegate to it without permission.*

*Ensures that:
1) the `staker` is not already delegated to an operator
2) the `operator` has indeed registered as an operator in EigenLayer*


```solidity
function delegateTo(address operator) external checkDelegator;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operator`|`address`|The account teh Strategy Vault is delegating its assets to for use in serving applications built on EigenLayer.|


### createEigenPod

Create an EigenPod for the StrategyVault.

*Can only be called by the StrategyVaultManager during the vault creation.*


```solidity
function createEigenPod() external onlyStratVaultManager;
```

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
) external onlyBeaconChainAdmin;
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
function startCheckpoint(bool revertIfNoBalance) external onlyBeaconChainAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`revertIfNoBalance`|`bool`|Forces a revert if the pod ETH balance is 0. This allows the pod owner to prevent accidentally starting a checkpoint that will not increase their shares|


### updateWhitelistedDeposit

Updates the whitelistedDeposit flag.

*Callable only by the owner of the Strategy Vault's ByzNft.*


```solidity
function updateWhitelistedDeposit(bool _whitelistedDeposit) external onlyNftOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_whitelistedDeposit`|`bool`|The new whitelistedDeposit flag.|


### whitelistStaker

Whitelist a staker.

*Callable only by the owner of the Strategy Vault's ByzNft.*


```solidity
function whitelistStaker(address staker) external onlyNftOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`staker`|`address`|The address to whitelist.|


### stratVaultOwner

Returns the address of the owner of the Strategy Vault's ByzNft.


```solidity
function stratVaultOwner() public view returns (address);
```

### hasDelegatedTo

Returns the Eigen Layer operator that the Strategy Vault is delegated to


```solidity
function hasDelegatedTo() public view returns (address);
```

### getVaultDVNumber

Returns the number of active DVs staked by the Strategy Vault.


```solidity
function getVaultDVNumber() public view returns (uint256);
```

### getAllDVIds

Returns the IDs of the active DVs staked by the Strategy Vault.


```solidity
function getAllDVIds() public view returns (bytes32[] memory);
```

### _triggerAuction


```solidity
function _triggerAuction() internal;
```

### _burnVaultShares


```solidity
function _burnVaultShares(uint256 amount, address receiver) internal;
```

### _getETHBalance


```solidity
function _getETHBalance() internal view override returns (uint256);
```

