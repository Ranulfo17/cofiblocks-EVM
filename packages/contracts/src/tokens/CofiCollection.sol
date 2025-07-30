// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title CofiCollection
 * @author CofiBlocks Cofounder
 * @notice Manages the creation and ownership of ERC1155 tokens representing batches of coffee.
 * @dev An upgradeable, pausable, role-based ERC1155 contract for the CofiBlocks ecosystem.
 * Each tokenId represents a unique coffee lot from a producer.
 */
contract CofiCollection is
    Initializable,
    ERC1155Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    /**
     * @dev Role for accounts authorized to create new tokens (mint).
     * Typically assigned to the Marketplace contract or a secure admin wallet.
     */
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @dev Role for accounts authorized to pause and unpause the contract's transfers.
     * This is an emergency stop mechanism.
     */
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @dev Role for accounts authorized to update the base URI for token metadata.
     */
    bytes32 public constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");
    
    /**
     * @dev Role for accounts authorized to upgrade the contract's implementation.
     */
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract, setting up roles and the initial base URI.
     * @dev This function replaces the constructor in an upgradeable contract pattern. It can only be called once.
     * @param defaultAdmin The address that will receive the DEFAULT_ADMIN_ROLE.
     * @param pauser The address for the PAUSER_ROLE.
     * @param minter The address for the MINTER_ROLE.
     * @param uriSetter The address for the URI_SETTER_ROLE.
     * @param upgrader The address for the UPGRADER_ROLE.
     */
    function initialize(
        address defaultAdmin,
        address pauser,
        address minter,
        address uriSetter,
        address upgrader
    ) public initializer {
        __ERC1155_init("ipfs://");
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(URI_SETTER_ROLE, uriSetter);
        _grantRole(UPGRADER_ROLE, upgrader);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlUpgradeable, ERC1155Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice Creates a new amount of a single token ID and assigns it to an address.
     * @dev Caller must have the MINTER_ROLE.
     * @param to The address to receive the tokens.
     * @param id The ID of the token to mint.
     * @param amount The quantity of tokens to mint.
     * @param data Additional data with no specified format.
     */
    function mint(address to, uint256 id, uint256 amount, bytes memory data) public virtual onlyRole(MINTER_ROLE) {
        _mint(to, id, amount, data);
    }

    /**
     * @notice Creates new amounts of multiple token IDs and assigns them to an address.
     * @dev Caller must have the MINTER_ROLE.
     * @param to The address to receive the tokens.
     * @param ids The list of token IDs to mint.
     * @param amounts The list of amounts to mint for each token ID.
     * @param data Additional data with no specified format.
     */
    function batchMint(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual onlyRole(MINTER_ROLE) {
        _mintBatch(to, ids, amounts, data);
    }

    /**
     * @notice Burns a specific amount of a single token ID from an account.
     * @dev Caller must be the `from` address or be approved by it.
     */
    function burn(address from, uint256 id, uint256 value) public virtual {
        _burn(from, id, value);
    }

    /**
     * @notice Burns amounts of multiple token IDs from an account.
     * @dev Caller must be the `from` address or be approved by it.
     */
    function batchBurn(address from, uint256[] memory ids, uint256[] memory values) public virtual {
        _burnBatch(from, ids, values);
    }

    /**
     * @notice Pauses all token transfers, mints, and burns.
     * @dev Caller must have the PAUSER_ROLE.
     */
    function pause() public virtual onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Resumes all token transfers, mints, and burns.
     * @dev Caller must have the PAUSER_ROLE.
     */
    function unpause() public virtual onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Updates the base URI for all token metadata.
     * @dev Caller must have URI_SETTER_ROLE. The final URI for a token is {baseURI}{tokenId}.
     * @param newURI The new base URI. E.g., "ipfs://your-hash/"
     */
    function setBaseURI(string memory newURI) public virtual onlyRole(URI_SETTER_ROLE) {
        _setURI(newURI);
    }

    /**
     * @notice Grants the MINTER_ROLE to a new address.
     * @dev Caller must have the DEFAULT_ADMIN_ROLE.
     * @param newMinter The address to grant the MINTER_ROLE to.
     */
    function setMinter(address newMinter) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(MINTER_ROLE, newMinter);
    }

    /**
     * @notice Returns the Uniform Resource Identifier (URI) for a given token ID.
     * @dev Overrides the base implementation to concatenate the base URI with the token ID,
     * which is the expected behavior for NFT metadata. Reverts if base URI is not set.
     * @param tokenId The ID of the token.
     * @return The URI string for the token's metadata.
     */
    function uri(uint256 tokenId) public view virtual override returns (string memory) {
        string memory baseURI = super.uri(tokenId);
        require(bytes(baseURI).length > 0, "ERC1155: URI not set or token does not exist");
        return string.concat(baseURI, Strings.toString(tokenId));
    }

    /**
     * @dev Internal hook that is called before any token transfer.
     * Overridden to enforce the pausable functionality.
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal virtual override(ERC1155Upgradeable) {
        _requireNotPaused();
        super._update(from, to, ids, amounts);
    }

    /**
     * @dev Internal hook to authorize an upgrade to a new implementation contract.
     * Overridden to restrict upgrade functionality to the UPGRADER_ROLE.
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(UPGRADER_ROLE) {}
}