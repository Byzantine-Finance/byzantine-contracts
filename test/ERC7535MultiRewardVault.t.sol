pragma solidity ^0.8.20;

import {ERC7535MultiRewardVault} from "../src/vault/ERC7535MultiRewardVault.sol";
import {Test} from "forge-std/Test.sol";

contract ERC7535MultiRewardVaultTest is Test {
    ERC7535MultiRewardVault vault;

    function setUp() public {
        vault = new ERC7535MultiRewardVault();
    }
}