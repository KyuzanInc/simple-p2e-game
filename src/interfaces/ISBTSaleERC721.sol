// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title ISBTSaleERC721
 * @dev Interface for ERC721 tokens that can be minted by SBTSale contract
 */
interface ISBTSaleERC721 is IERC721 {
    /**
     * @dev Mint a new SBT to the specified address with specified token ID
     * @param to Address to mint the SBT to
     * @param tokenId Token ID to mint
     */
    function safeMint(address to, uint256 tokenId) external;
}
