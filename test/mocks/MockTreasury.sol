// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev TEST ONLY introspection fixture. Not a wallet; calls are simulated using vm.prank.
contract MockTreasury {
    address[] private owners;
    uint256 private threshold = 2;

    constructor(address first, address second, address third) {
        owners.push(first);
        owners.push(second);
        owners.push(third);
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getThreshold() external view returns (uint256) {
        return threshold;
    }

    function setThreshold(uint256 value) external {
        threshold = value;
    }

    function setOwner(uint256 index, address owner) external {
        owners[index] = owner;
    }
}
