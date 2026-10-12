
 // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBMCIlluminatiPass is IERC721 {
    enum Tier {
        Pending,
        LegendaryGenesis,
        Genesis,
        Standard
    }

    function tierOf(uint256 tokenId)
        external
        view
        returns (Tier);

    function artworkIdOf(uint256 tokenId)
        external
        view
        returns (uint16);
}
function totalSupply() external view returns (uint256);
