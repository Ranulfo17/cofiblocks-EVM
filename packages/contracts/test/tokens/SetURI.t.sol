// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CofiCollection} from "src/tokens/CofiCollection.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SetURITest is Test {
    CofiCollection internal collection;

    // Atores necessários para este teste
    address internal uriSetter = makeAddr("uriSetter");
    address internal attacker = makeAddr("attacker");

    // Hash do Role
    bytes32 internal constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");

    function setUp() public {
        // Deploy do contrato
        CofiCollection implementation = new CofiCollection();
        
        // Apenas o papel 'uriSetter' é necessário para este teste.
        bytes memory data = abi.encodeWithSelector(
            CofiCollection.initialize.selector,
            address(0),   // admin
            address(0),   // pauser
            address(0),   // minter
            uriSetter,    // uriSetter
            address(0)    // upgrader
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        collection = CofiCollection(address(proxy));
    }

    function test_SetBaseURI_SucceedsForUriSetterRole() public {
        string memory newURI = "ipfs://new-collection-hash/";

        // O chamador (msg.sender) é a conta com o papel de URI_SETTER_ROLE
        vm.prank(uriSetter);
        collection.setBaseURI(newURI);

        // Verifica se a URI para um token de exemplo foi atualizada corretamente
        assertEq(collection.uri(1), string.concat(newURI, "1"), "A baseURI nao foi atualizada corretamente");
    }

    function test_RevertWhen_SetBaseURI_CalledByNonRole() public {
        // Prepara o erro esperado: falha de controle de acesso
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                attacker,
                URI_SETTER_ROLE
            )
        );

        // O chamador (msg.sender) é uma conta não autorizada
        vm.prank(attacker);
        collection.setBaseURI("ipfs://hacker-uri/");
    }
}