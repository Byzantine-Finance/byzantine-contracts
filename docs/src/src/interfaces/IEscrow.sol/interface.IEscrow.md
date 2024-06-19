# IEscrow
[Git Source](https://github.com/Byzantine-Finance/byzantine-contracts/blob/80b6cda4622c51c2217311610eeb15b655b99e2c/src/interfaces/IEscrow.sol)


## Functions
### releaseFunds

Function to approve the bid price of the winner operator to be released to the bid price receiver


```solidity
function releaseFunds(uint256 _bidPrice) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_bidPrice`|`uint256`|Bid price of the node operator|


### refund

Function to refund the overpaid amount to the node operator after bidding or updating its bid.
Also used to refund the node operator when he withdraws


```solidity
function refund(address _nodeOpAddr, uint256 _amountToRefund) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOpAddr`|`address`|Address of the node operator to refund|
|`_amountToRefund`|`uint256`|Funds to be refunded to the node operator if necessary|


## Events
### FundsLocked

```solidity
event FundsLocked(uint256 _amount);
```

## Errors
### OnlyAuction
*Error when unauthorized call to a function callable only by the Auction.*


```solidity
error OnlyAuction();
```

### InsufficientFundsInEscrow
*Returned when not enough funds in the escrow to refund ops or move funds.*


```solidity
error InsufficientFundsInEscrow();
```

### FailedToSendEther
Returned when failed to send Ether to the bid price receiver or to bidder


```solidity
error FailedToSendEther();
```

