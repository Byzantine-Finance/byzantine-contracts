// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/interfaces/IOracle.sol";

contract MockOracle is IOracle {
    function getPrice(address) external pure override returns (uint256) {
        // Return $1000 USD with 18 decimal places
        return 1000 * 1e18;
    }
}
