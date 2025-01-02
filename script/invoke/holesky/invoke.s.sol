// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {StrategyVaultETH} from "../../../src/core/StrategyVaultETH.sol";
import {Auction} from "../../../src/core/Auction.sol";
import {IAuction} from "../../../src/interfaces/IAuction.sol";

/**
 * @notice Script used to interact with Byzantine's contracts using Foundry
 * forge script script/invoke/holesky/invoke.s.sol --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY_DEPOSITOR --broadcast -vvvv
 * forge script script/invoke/holesky/invoke.s.sol --rpc-url $HOLESKY_RPC_URL --private-key $PRIVATE_KEY_DEPOSITOR --broadcast -vvvv
 * 
 */
contract Invoke is Script {

    address constant STRATEGY_VAULT_ETH_ADDRESS = 0x5db1A17cB543997F8b3D7e6f8A544041507B9DA6;
    address constant AUCTION_ADDRESS = 0xC050C50e18CB8787dDF1E1227c0FE7A8a5404815;

    function run() external {

        // Commencer la transaction
        vm.startBroadcast();

        // _stake32ETHInVault(STRATEGY_VAULT_ETH_ADDRESS);
        _getBidsRanking(20);

        // Fin de la transaction
        vm.stopBroadcast();
    }

    // Display the auction bids ranking
    function _getBidsRanking(uint256 _numBids) internal {
        Auction auction = Auction(payable(AUCTION_ADDRESS));

        uint256 numBids = auction.getNumBids(IAuction.AuctionType.JOIN_CLUSTER_4);
        console.log("Total numBids: ", numBids);

        IAuction.BSTNode[] memory bstNodes = auction.getBidRanking(_numBids, IAuction.AuctionType.JOIN_CLUSTER_4);
        for (uint256 i = 0; i < bstNodes.length; i++) {
            console.log("--------------> bid index: ", i);
            console.logBytes32(bstNodes[i].bidId);
            console.log("auction score", bstNodes[i].auctionScore);
            _logBidDetails(bstNodes[i].bidId);
        }
    }

    // Stake 32 ETH in specified vault
    function _stake32ETHInVault(address _vaultAddress) internal {
        StrategyVaultETH strategyVaultETH = StrategyVaultETH(payable(_vaultAddress));
        strategyVaultETH.deposit{value: 32 ether}(32 ether, msg.sender);
    }

    // Admin removes bid from auction
    function _removeBid(bytes32 _bidId, uint256 _auctionScore, address _nodeOp) internal {
        Auction auction = Auction(payable(AUCTION_ADDRESS));
        auction.removeBid(_bidId, _auctionScore, _nodeOp, IAuction.AuctionType.JOIN_CLUSTER_4);
    }

    // Display bid details
    function _logBidDetails(bytes32 _bidId) internal {
        Auction auction = Auction(payable(AUCTION_ADDRESS));
        IAuction.BidDetails memory bidDetails = auction.getBidDetails(_bidId);
        console.log("Bid auction score:", bidDetails.auctionScore);
        console.log("Bid price:", bidDetails.bidPrice);
        console.log("Node operator address:", bidDetails.nodeOp);
        console.log("VC number:", bidDetails.vcNumber); 
        console.log("Discount rate:", bidDetails.discountRate);
        console.log("Auction type:", uint8(bidDetails.auctionType));
    }    
    
}