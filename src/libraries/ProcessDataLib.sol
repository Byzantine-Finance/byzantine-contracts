// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/*
Hitchens UnorderedaddrSet v0.93

Library for managing CRUD operations in dynamic addr sets.

https://github.com/rob-Hitchens/UnorderedaddrSet

Copyright (c), 2019, Rob Hitchens, the MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

THIS SOFTWARE IS NOT TESTED OR AUDITED. DO NOT USE FOR PRODUCTION.
*/

library ProcessDataLib {
    struct Set {
        /// maps address => index of the addr stored in the addrList
        mapping(address => uint) addrPointers;
        address[] addrList;
    }

    function insert(Set storage self, address addr) internal {
        require(addr != address(0), "UnorderedaddrSet(100) - addr cannot be 0x0");
        require(!exists(self, addr), "UnorderedaddrSet(101) - addr already exists in the set.");
        self.addrList.push(addr);
        self.addrPointers[addr] = self.addrList.length - 1;
    }

    function remove(Set storage self, address addr) internal {
        require(exists(self, addr), "UnorderedaddrSet(102) - addr does not exist in the set.");
        address addrToMove = self.addrList[count(self) - 1];
        uint rowToReplace = self.addrPointers[addr];
        self.addrPointers[addrToMove] = rowToReplace;
        self.addrList[rowToReplace] = addrToMove;
        delete self.addrPointers[addr];
        self.addrList.pop();
    }

    function count(Set storage self) internal view returns (uint) {
        return (self.addrList.length);
    }

    function exists(Set storage self, address addr) internal view returns (bool) {
        if (self.addrList.length == 0) return false;
        return self.addrList[self.addrPointers[addr]] == addr;
    }

    function addrAtIndex(Set storage self, uint index) internal view returns (address) {
        return self.addrList[index];
    }

    function nukeSet(Set storage self) internal {
        delete self.addrList;
    }
}
