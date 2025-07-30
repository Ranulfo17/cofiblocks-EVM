// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {CofiCollection} from "src/tokens/CofiCollection.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract CofiCollectionTest is Test {
    CofiCollection internal collection;
    address internal proxyAddress;

    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal minter = makeAddr("minter");
    address internal uriSetter = makeAddr("uriSetter");
    address internal upgrader = makeAddr("upgrader");
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");
    address internal attacker = makeAddr("attacker");

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");
    bytes32 internal constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        CofiCollection implementation = new CofiCollection();
        bytes memory data = abi.encodeWithSelector(CofiCollection.initialize.selector, admin, pauser, minter, uriSetter, upgrader);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        proxyAddress = address(proxy);
        collection = CofiCollection(proxyAddress);
    }

    function test_Initialization_RolesAreSetCorrectly() public view {
        assertTrue(collection.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(collection.hasRole(PAUSER_ROLE, pauser));
        assertTrue(collection.hasRole(MINTER_ROLE, minter));
        assertTrue(collection.hasRole(URI_SETTER_ROLE, uriSetter));
        assertTrue(collection.hasRole(UPGRADER_ROLE, upgrader));
    }

    function test_Mint_SucceedsForMinter() public {
        vm.prank(minter);
        collection.mint(user1, 1, 100, "");
        assertEq(collection.balanceOf(user1, 1), 100);
    }

    function test_RevertWhen_Mint_CalledByNonMinter() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), attacker, MINTER_ROLE));
        vm.prank(attacker);
        collection.mint(user1, 1, 100, "");
    }

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

    function test_Unpause_TransfersShouldSucceedWhenUnpaused() public {
        // 1. Minter cria o token para user1
        vm.prank(minter);
        collection.mint(user1, 1, 100, "");

        // 2. Pauser pausa e depois despausa, usando startPrank para múltiplas chamadas
        vm.startPrank(pauser);
        collection.pause();
        collection.unpause();
        vm.stopPrank();
        assertFalse(collection.paused(), "O contrato deveria estar despausado");

        // 3. Dono do token (user1) agora consegue transferir com sucesso
        vm.prank(user1);
        collection.safeTransferFrom(user1, user2, 1, 50, "");
        assertEq(collection.balanceOf(user2, 1), 50, "A transferencia deveria ocorrer apos despausar");
    }

    function test_Upgradeability_CanUpgradeToNewImplementation() public {
        CofiCollectionV2 newImplementation = new CofiCollectionV2();
        vm.prank(upgrader);
        collection.upgradeToAndCall(address(newImplementation), "");
        CofiCollectionV2 upgradedCollection = CofiCollectionV2(proxyAddress);
        assertEq(upgradedCollection.version(), "v2");
    }

    function testFuzz_MintAndBurn(uint96 tokenId, uint128 amount, address recipient) public {
        vm.assume(recipient != address(0) && amount > 0);
        vm.prank(minter);
        collection.mint(recipient, tokenId, amount, "");
        assertEq(collection.balanceOf(recipient, tokenId), amount);
        vm.prank(recipient);
        collection.burn(recipient, tokenId, amount);
        assertEq(collection.balanceOf(recipient, tokenId), 0);
    }

    CofiCollectionHandler internal handler;

    function setUpInvariantTesting() public {
        handler = new CofiCollectionHandler(collection, minter);
        targetContract(address(handler));
    }

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

contract CofiCollectionHandler is Test {
    CofiCollection internal collection;
    address[] public actors;
    address internal minter;
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

    function getActors() public view returns (address[] memory) {
        return actors;
    }

    function getKnownIdsLength() public view returns (uint256) {
        return knownIds.length;
    }

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

contract CofiCollectionV2 is CofiCollection {
    function version() public pure returns (string memory) {
        return "v2";
    }
}