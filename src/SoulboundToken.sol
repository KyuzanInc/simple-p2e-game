// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC721PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ISBTSaleERC721} from "./interfaces/ISBTSaleERC721.sol";

/**
 * @title SoulboundToken
 * @notice ERC721 Soulbound Token with Pausable and Enumerable features
 * @dev Tokens are non-transferable, pausable, and enumerable. Contract is upgradeable.
 */
contract SoulboundToken is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721PausableUpgradeable,
    AccessControlUpgradeable,
    ISBTSaleERC721
{
    /// @dev Error for invalid owner
    error InvalidOwner();

    /// @dev Revert when attempting a prohibited transfer or approval
    error Soulbound();

    /// @notice Role identifier for accounts allowed to mint
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role identifier for accounts allowed to pause
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Base URI for token metadata
    string private _baseTokenURI;

    /// @dev Token mint timestamp mapping
    mapping(uint256 => uint256) private _mintedAt;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the SBT contract
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param baseURI_ Initial base URI for token metadata
     * @param owner_ Initial contract owner and admin
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address owner_
    ) public initializer {
        if (owner_ == address(0)) {
            revert InvalidOwner();
        }

        __ERC721_init(name_, symbol_);
        __ERC721Enumerable_init();
        __ERC721Pausable_init();
        __AccessControl_init();

        _baseTokenURI = baseURI_;

        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
        _grantRole(MINTER_ROLE, owner_);
        _grantRole(PAUSER_ROLE, owner_);
    }

    /**
     * @notice Mint a new SBT with specified token ID
     * @param to Recipient address
     * @param tokenId Token ID to mint
     */
    function safeMint(address to, uint256 tokenId)
        external
        override(ISBTSaleERC721)
        onlyRole(MINTER_ROLE)
    {
        _safeMint(to, tokenId);
        _mintedAt[tokenId] = block.timestamp;
    }

    /// @notice Update base URI for token metadata
    function setBaseURI(string memory newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
    }

    /// @notice Pause the contract (prevents minting)
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract (allows minting)
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice View mint timestamp of a token
    function mintTimeOf(uint256 tokenId) external view returns (uint256) {
        return _mintedAt[tokenId];
    }

    /// @dev Returns the base URI for all tokens
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @dev Override required by multiple inheritance
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    /// @dev Override required by ERC721EnumerableUpgradeable
    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._increaseBalance(account, value);
    }

    /// @inheritdoc ERC721Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ---------------------------------------------------------------------
    // Non-transferable overrides
    // ---------------------------------------------------------------------

    /// @dev Override approval to prevent any approvals
    function approve(address, uint256) public pure override(ERC721Upgradeable, IERC721) {
        revert Soulbound();
    }

    /// @dev Override setApprovalForAll to prevent any approvals
    function setApprovalForAll(address, bool) public pure override(ERC721Upgradeable, IERC721) {
        revert Soulbound();
    }

    /// @dev Override transferFrom to prevent any transfers
    function transferFrom(address, address, uint256)
        public
        pure
        override(ERC721Upgradeable, IERC721)
    {
        revert Soulbound();
    }

    /// @dev Override the internal _safeTransfer function to prevent any transfers
    function _safeTransfer(address, address, uint256, bytes memory) internal pure override {
        revert Soulbound();
    }
}
