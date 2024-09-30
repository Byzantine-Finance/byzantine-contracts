// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Library which implements a FIFO (First In First Out) logic
/// @notice The FIFO elements must be non-repeating and non-null
/// @dev The library is used to handle the clusterIds in the StrategyVaultETH contract storage
library FIFOLib {

    struct FIFOElement {
        bytes32 id;
        bytes32 nextId;
    }

    struct FIFO {
        FIFOElement head;
        FIFOElement tail;
        mapping(bytes32 => FIFOElement) element;
        uint256 count;
    }

    function push(FIFO storage self, bytes32 _id) internal {
        FIFOElement memory head = self.head;
        ++self.count;
        if (head.id != bytes32(0)) { // head exists
            FIFOElement memory tail = self.tail;
            if (tail.id != bytes32(0)) { // tail exists
                self.element[tail.id].nextId = _id; // set old tail next id
            } else { // tail does not exist
                self.head.nextId = _id;
                self.element[head.id] = FIFOElement(head.id, _id);
            }
            FIFOElement memory newTail = FIFOElement(_id, bytes32(0));
            self.element[_id] = newTail;
            self.tail = newTail;
            return;
        } // else head.id == 0, so just set head
        self.head.id = _id;
        self.element[_id] = FIFOElement(_id, bytes32(0));
    }

    function pop(FIFO storage self) internal returns (bytes32) {
        FIFOElement memory head = self.head;
        require(head.id != bytes32(0), "FIFO: pop from empty FIFO");
        --self.count;
        bytes32 id = head.id;
        if (head.nextId != bytes32(0)) { // verify if other elements
            self.head = self.element[head.nextId];
            // if next element if null, head is also the tail
            if (self.head.nextId == bytes32(0)) delete self.tail;
            return id;
        } // else only head in fifo
        delete self.head;
        return id;
    }

    function getNumElements(FIFO storage self) internal view returns (uint256) {
        return self.count;
    }

    function getAllElements(FIFO storage self) internal view returns (bytes32[] memory) {
        bytes32[] memory ids = new bytes32[](self.count);
        
        bytes32 currentId = self.head.id;
        for (uint256 i = 0; i < self.count;) {
            ids[i] = currentId;
            currentId = self.element[currentId].nextId;
            unchecked {
                ++i;
            }
        }
        
        return ids;
    }

}