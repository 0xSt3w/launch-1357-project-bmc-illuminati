// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Safe-compatible introspection; deployment review must verify implementation and modules.
interface IMultisigTreasury {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
}
