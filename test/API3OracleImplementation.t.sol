// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/oracle/API3OracleImplementation.sol";

contract API3OracleImplementationTest is Test {
    API3OracleImplementation public oracle;

    function setUp() public {
        oracle = new API3OracleImplementation();
    }

    /// @dev forge test --fork-url $HOLESKY_RPC_URL --match-path test/API3OracleImplementation.t.sol
    /// @dev This test interacts with a live contract and may produce different results each time it's run.
    function testGetETHUSDPrice() public {
        uint256 price;

        // Check if running on a local environment
        if (block.chainid == 31337) { // Assuming 31337 is the local chain ID
            // Mock the price for local testing
            price = 3000 * 1e18; // Mock price of $3000
        } else {
            // Fetch the price from the live contract
            price = oracle.getPrice(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
        }

        console.log("Current ETH/USD price: $", price / 1e18);

        // Basic sanity checks
        assertTrue(price > 0, "Price should be greater than 0");
        assertTrue(price < 1e23, "Price should be less than $100,000");
    }
}