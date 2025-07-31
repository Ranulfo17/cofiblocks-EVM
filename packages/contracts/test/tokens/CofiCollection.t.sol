// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {CofiCollection} from "src/tokens/CofiCollection.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title Test Suite for CofiCollection
 * @author CofiBlocks Team
 * @dev This contract tests all functionality of the CofiCollection contract,
 * including unit tests, fuzz tests, and invariant tests.
 */
contract CofiCollectionTest is Test {
    /// @dev The main contract instance under test, accessed via its proxy.
    CofiCollection internal collection;
    /// @dev The address of the ERC1967 proxy contract.
    address internal proxyAddress;

    // --- Test Personas ---
    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal minter = makeAddr("minter");
    address internal uriSetter = makeAddr("uriSetter");
    address internal upgrader = makeAddr("upgrader");
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");
    address internal attacker = makeAddr("attacker");

    // --- Role Hashes ---
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");
    bytes32 internal constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Deploys a fresh CofiCollection proxy instance before each test.
     */
    function setUp() public {
        CofiCollection implementation = new CofiCollection();
        bytes memory data = abi.encodeWithSelector(CofiCollection.initialize.selector, admin, pauser, minter, uriSetter, upgrader);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        proxyAddress = address(proxy);
        collection = CofiCollection(proxyAddress);
    }

    // =================================
    //         Unit Tests
    // =================================

    /// @dev Tests if roles are correctly assigned during contract initialization.
    function test_Initialization_RolesAreSetCorrectly() public view {
        assertTrue(collection.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(collection.hasRole(PAUSER_ROLE, pauser));
        assertTrue(collection.hasRole(MINTER_ROLE, minter));
        assertTrue(collection.hasRole(URI_SETTER_ROLE, uriSetter));
        assertTrue(collection.hasRole(UPGRADER_ROLE, upgrader));
    }

    /// @dev Tests that an account with MINTER_ROLE can successfully mint tokens.
    function test_Mint_SucceedsForMinter() public {
        vm.prank(minter);
        collection.mint(user1, 1, 100, "");
        assertEq(collection.balanceOf(user1, 1), 100);
    }

    /// @dev Tests that a call to mint() from an unauthorized account correctly reverts.
    function test_RevertWhen_Mint_CalledByNonMinter() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), attacker, MINTER_ROLE));
        vm.prank(attacker);
        collection.mint(user1, 1, 100, "");
    }

    /// @dev Tests that token transfers revert when the contract is paused.
    function test_Pause_TransfersShouldFailWhenPaused() public {
        vm.prank(minter);
        collection.mint(user1, 1, 100, "");
        vm.prank(pauser);
        collection.pause();
        assertTrue(collection.paused());
        vm.prank(user1);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        collection.safeTransferFrom(user1, user2, 1, 50, "");
    }

    /// @dev Tests that token transfers succeed after the contract is unpaused.
    function test_Unpause_TransfersShouldSucceedWhenUnpaused() public {
        // 1. Minter creates the token for user1
        vm.prank(minter);
        collection.mint(user1, 1, 100, "");

        // 2. Pauser pauses and then unpauses the contract
        vm.startPrank(pauser);
        collection.pause();
        collection.unpause();
        vm.stopPrank();
        assertFalse(collection.paused(), "Contract should be unpaused");

        // 3. The token owner (user1) can now successfully transfer
        vm.prank(user1);
        collection.safeTransferFrom(user1, user2, 1, 50, "");
        assertEq(collection.balanceOf(user2, 1), 50, "Transfer should succeed after unpause");
    }

    /// @dev Tests that the contract can be successfully upgraded to a new implementation via the UUPS proxy pattern.
    function test_Upgradeability_CanUpgradeToNewImplementation() public {
        CofiCollectionV2 newImplementation = new CofiCollectionV2();
        vm.prank(upgrader);
        collection.upgradeToAndCall(address(newImplementation), "");
        CofiCollectionV2 upgradedCollection = CofiCollectionV2(proxyAddress);
        assertEq(upgradedCollection.version(), "v2");
    }

    // =================================
    //         Fuzz Tests
    // =================================

    /// @dev Fuzzes the mint and burn functions to ensure balance accounting is correct across a wide range of inputs.
    function testFuzz_MintAndBurn(uint96 tokenId, uint128 amount, address recipient) public {
        vm.assume(recipient != address(0) && amount > 0);
        vm.prank(minter);
        collection.mint(recipient, tokenId, amount, "");
        assertEq(collection.balanceOf(recipient, tokenId), amount);
        vm.prank(recipient);
        collection.burn(recipient, tokenId, amount);
        assertEq(collection.balanceOf(recipient, tokenId), 0);
    }
    
    // =================================
    //       Invariant Tests
    // =================================

    CofiCollectionHandler internal handler;

    /// @dev Sets up the handler contract for stateful fuzzing required by invariant tests.
    function setUpInvariantTesting() public {
        handler = new CofiCollectionHandler(collection, minter);
        targetContract(address(handler));
    }

    /// @dev Invariant: The sum of all individual balances for any token ID must always equal the total supply tracked by the handler.
    function invariant_TotalSupplyIsConsistent() public {
        setUpInvariantTesting();
        uint256 knownIdsLength = handler.getKnownIdsLength();
        for (uint i = 0; i < knownIdsLength; ++i) {
            uint256 tokenId = handler.knownIds(i);
            uint256 ghostTotalSupply = handler.ghostTotalSupply(tokenId);
            uint256 realTotalSupply = 0;
            address[] memory actors = handler.getActors();
            for (uint j = 0; j < actors.length; ++j) {
                realTotalSupply += collection.balanceOf(actors[j], tokenId);
            }
            assertEq(realTotalSupply, ghostTotalSupply, "Total supply mismatch");
        }
    }
}

/**
 * @title Handler for Invariant Testing
 * @dev A stateful contract that performs a sequence of actions on CofiCollection 
 * for the Foundry invariant testing engine. It uses ghost variables to mirror
 * the state of the main contract and verify its properties.
 */
contract CofiCollectionHandler is Test {
    CofiCollection internal collection;
    address[] public actors;
    address internal minter;

    // --- Ghost Variables ---
    mapping(uint256 => uint256) public ghostTotalSupply;
    uint256[] public knownIds;
    mapping(uint256 => bool) private idExists;

    constructor(CofiCollection _collection, address _minter) {
        collection = _collection;
        minter = _minter;
        actors.push(makeAddr("inv_user_1"));
        actors.push(makeAddr("inv_user_2"));
        actors.push(makeAddr("inv_user_3"));
    }

    /// @dev Getter for the list of actors, required for inter-contract array access in tests.
    function getActors() public view returns (address[] memory) {
        return actors;
    }

    /// @dev Getter for the length of known token IDs, required for inter-contract array access in tests.
    function getKnownIdsLength() public view returns (uint256) {
        return knownIds.length;
    }

    /// @dev Handler function that calls the mint function on the main contract with fuzzed inputs.
    function mint(uint96 tokenId, uint128 amount, uint256 actorSeed) public {
        amount = uint128(bound(amount, 1, 10e18));
        address recipient = actors[actorSeed % actors.length];
        vm.prank(minter);
        collection.mint(recipient, tokenId, amount, "");
        ghostTotalSupply[tokenId] += amount;
        if (!idExists[tokenId]) {
            idExists[tokenId] = true;
            knownIds.push(tokenId);
        }
    }

    /// @dev Handler function that calls the burn function on the main contract with fuzzed inputs.
    function burn(uint96 tokenId, uint128 amount, uint256 actorSeed) public {
        if (knownIds.length == 0) return;
        tokenId = uint96(knownIds[tokenId % knownIds.length]);
        address owner = actors[actorSeed % actors.length];
        uint256 balance = collection.balanceOf(owner, tokenId);
        amount = uint128(bound(amount, 0, balance));
        if (amount == 0) return;
        vm.prank(owner);
        collection.burn(owner, tokenId, amount);
        ghostTotalSupply[tokenId] -= amount;
    }

    /// @dev Handler function that calls the safeTransferFrom function with fuzzed inputs.
    function safeTransferFrom(uint96 tokenId, uint128 amount, uint256 fromSeed, uint256 toSeed) public {
        if (knownIds.length == 0) return;
        tokenId = uint96(knownIds[tokenId % knownIds.length]);
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.assume(from != to);
        uint256 balance = collection.balanceOf(from, tokenId);
        amount = uint128(bound(amount, 0, balance));
        if (amount == 0) return;
        vm.prank(from);
        collection.safeTransferFrom(from, to, tokenId, amount, "");
    }
}

/**
 * @dev A mock V2 contract used solely to test the upgrade functionality of the main contract.
 */
contract CofiCollectionV2 is CofiCollection {
    function version() public pure returns (string memory) {
        return "v2";
    }
}