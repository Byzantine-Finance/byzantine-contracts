// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOracle {
    function getPrice(address asset, address priceFeed) external view returns (uint256);
}