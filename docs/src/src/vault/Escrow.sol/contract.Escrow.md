# Escrow
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/9fb891800d52aaca6ef4f8a781c3003290fa4d2f/src/vault/Escrow.sol)

**Inherits:**
[IEscrow](/src/interfaces/IEscrow.sol/interface.IEscrow.md)


## State Variables
### stakerRewards
Address which receives the bid of the auction winners

*This will be updated to a smart contract vault in the future to distribute the stakers rewards*


```solidity
IStakerRewards public immutable stakerRewards;
```


### auction
Auction contract


```solidity
IAuction public immutable auction;
```


## Functions
### constructor

Constructor to set the stakerRewards and the auction contracts


```solidity
constructor(IStakerRewards _stakerRewards, IAuction _auction);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_stakerRewards`|`IStakerRewards`|Address which receives the bid of the winners and distribute it to the stakers|
|`_auction`|`IAuction`|The auction proxy contract|


### receive

Fallback function which receives funds of the node operator when they bid
Also receives new funds after a node operator updates its bid

*The funds are locked in the escrow*


```solidity
receive() external payable;
```

### releaseFunds

Function to approve the bid price of the winner operator to be released to the bid price receiver


```solidity
function releaseFunds(uint256 _bidPrice) public onlyAuction;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidPrice`|`uint256`|Bid price of the node operator|


### refund

Function to refund the overpaid amount to the node operator after bidding or updating its bid.
Also used to refund the node operator when he withdraws


```solidity
function refund(address _nodeOpAddr, uint256 _amountToRefund) public onlyAuction;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`|Address of the node operator to refund|
|`_amountToRefund`|`uint256`|Funds to be refunded to the node operator if necessary|


### onlyAuction


```solidity
modifier onlyAuction();
```

