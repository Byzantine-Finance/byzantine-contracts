// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/vault/ERC7535/ERC7535Upgradeable.sol";

contract StakingMinivaultMock is ERC7535Upgradeable {

    /* ============== EXTERNAL FUNCTIONS ============== */

    /**
     * @notice Payable fallback function that receives ether deposited to the StakingMinivault contract
     */
    receive() external override payable {}
}