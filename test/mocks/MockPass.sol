// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IBMCIlluminatiPass} from "../../src/interfaces/IBMCIlluminatiPass.sol";

/// @dev TEST ONLY: proves the proposed integration semantics, not the real collection implementation.
contract MockPass is ERC721, IBMCIlluminatiPass {
    mapping(uint256 => Tier) private tiers;
    mapping(uint256 => bool) private artworkAssigned;
    bool public brokenMetadata;

    constructor() ERC721("Test-only Illuminati Pass", "MOCKPASS") {}

    function mint(address to, uint256 tokenId, Tier tier, bool assigned) external {
        _mint(to, tokenId);
        tiers[tokenId] = tier;
        artworkAssigned[tokenId] = assigned;
    }

    function reveal(uint256 tokenId, Tier tier) external {
        tiers[tokenId] = tier;
        artworkAssigned[tokenId] = true;
    }

    function setBrokenMetadata(bool broken) external {
        brokenMetadata = broken;
    }

    function tierOf(uint256 tokenId) external view returns (Tier) {
        require(!brokenMetadata, "metadata unavailable");
        return tiers[tokenId];
    }

    function isArtworkAssigned(uint256 tokenId) external view returns (bool) {
        require(!brokenMetadata, "metadata unavailable");
        return artworkAssigned[tokenId];
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IBMCIlluminatiPass).interfaceId || super.supportsInterface(interfaceId);
    }
}
