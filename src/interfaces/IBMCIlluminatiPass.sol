// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Proposed integration ABI, NOT a claim about an already deployed collection.
/// @dev The independently reviewed collection must implement these exact semantics before use.
interface IBMCIlluminatiPass is IERC721 {
    enum Tier {
        Pending,
        Standard,
        RandomGenesis,
        EarlyGenesis,
        LegendaryGenesis
    }

    /// @dev A non-Pending tier must be final once artwork is assigned.
    function tierOf(uint256 tokenId) external view returns (Tier);

    /// @dev True only after the final artwork AND rarity assignment, not just a placeholder URI.
    function isArtworkAssigned(uint256 tokenId) external view returns (bool);
}
