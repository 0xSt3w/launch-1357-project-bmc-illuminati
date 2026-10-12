
 // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IBMCIlluminatiPass} from "../../src/interfaces/IBMCIlluminatiPass.sol";

/// @notice Test-only mock matching the real BMC PASS interface.
contract MockPass is ERC721, IBMCIlluminatiPass {
    mapping(uint256 => Tier) private tiers;
    mapping(uint256 => uint16) private artworkIds;

    uint256 private mintedCount;
    bool public brokenMetadata;

    constructor()
        ERC721("Test-only Illuminati Pass", "MOCKPASS")
    {}

    function mint(
        address to,
        uint256 tokenId,
        Tier tier,
        bool assigned
    ) external {
        _mint(to, tokenId);

        tiers[tokenId] = tier;

        if (assigned && tier != Tier.Pending) {
            artworkIds[tokenId] = _defaultArtwork(tokenId, tier);
        }

        mintedCount++;
    }

    function reveal(uint256 tokenId, Tier tier) external {
        require(_ownerOf(tokenId) != address(0), "not minted");
        tiers[tokenId] = tier;
        artworkIds[tokenId] = _defaultArtwork(tokenId, tier);
    }

    function setBrokenMetadata(bool broken) external {
        brokenMetadata = broken;
    }

    function tierOf(uint256 tokenId)
        external
        view
        returns (Tier)
    {
        require(!brokenMetadata, "metadata unavailable");
        require(_ownerOf(tokenId) != address(0), "not minted");
        return tiers[tokenId];
    }

    function artworkIdOf(uint256 tokenId)
        external
        view
        returns (uint16)
    {
        require(!brokenMetadata, "metadata unavailable");
        require(_ownerOf(tokenId) != address(0), "not minted");
        return artworkIds[tokenId];
    }

    function totalSupply() external view returns (uint256) {
        return mintedCount;
    }

    function _defaultArtwork(uint256 tokenId, Tier tier)
        private
        pure
        returns (uint16)
    {
        if (tier == Tier.Pending) return 0;

        if (tier == Tier.LegendaryGenesis) return 1;

        if (tier == Tier.Genesis) {
            if (tokenId <= 40) return uint16(tokenId);
            return uint16(41 + ((tokenId - 41) % 37));
        }

        if (tier == Tier.Standard) {
            return uint16(1 + ((tokenId - 41) % 423));
        }

        return 0;
    }
}
