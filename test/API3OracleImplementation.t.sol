// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/oracle/API3OracleImplementation.sol";
contract API3OracleImplementationTest is Test {
    API3OracleImplementation public oracle;
    address constant ETH_USD_PROXY = 0xa47Fd122b11CdD7aad7c3e8B740FB91D83Ce43D1; // ETH/USD Proxy on Holesky
    function setUp() public {
        oracle = new API3OracleImplementation();
    }

    /// @dev forge test --fork-url $HOLESKY_RPC_URL --match-path test/API3OracleImplementation.t.sol
    /// @dev This test interacts with a live contract and may produce different results each time it's run.
    function testGetETHUSDPrice() public {
        uint256 price = oracle.getPrice(address(0), ETH_USD_PROXY);
        
        console.log("Current ETH/USD price: $", price / 1e18);
        
        // Basic sanity checks
        assertTrue(price > 0, "Price should be greater than 0");
        assertTrue(price < 1e23, "Price should be less than $100,000");
    }
}