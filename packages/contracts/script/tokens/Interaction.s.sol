// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {CofiCollection} from "src/tokens/CofiCollection.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract FullFlowScript is Script {
    // --- Personas e Chaves Privadas (Padrão Anvil) ---
    uint256 internal constant ADMIN_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 internal constant PAUSER_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 internal constant MINTER_PK = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 internal constant PCF1_PK = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
    uint256 internal constant PCF2_PK = 0x47e179ec197488593b187f80a00e12e7f08b4051cc59954f2741ad1028234679;
    uint256 internal constant MARKETPLACE_PK = 0x8b3a350cf5c34c9194de1959318a7a5f2db548483957816abaaa74af73b37dc1;
    uint256 internal constant CCF1_PK = 0x92db14e403b83dfe3df233c83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec15991;
    uint256 internal constant CCF2_PK = 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356;

    address internal admin = vm.addr(ADMIN_PK);
    address internal pauser = vm.addr(PAUSER_PK);
    address internal minter = vm.addr(MINTER_PK);
    address internal pCF1 = vm.addr(PCF1_PK);
    address internal pCF2 = vm.addr(PCF2_PK);
    address internal marketplace = vm.addr(MARKETPLACE_PK);
    address internal cCF1 = vm.addr(CCF1_PK);
    address internal cCF2 = vm.addr(CCF2_PK);
    
    CofiCollection internal collection;
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function run() public {
        _deployContract();
        _testAccessControl();
        _testAssetLifecycle();
        _testSecurityFeatures();
        console.log("\nSCRIPT CONCLUIDO COM SUCESSO!");
    }

    // --- FUNÇÃO AUXILIAR DE DEPURAÇÃO (CORRIGIDA) ---
    function _logBalance(string memory actorName, address actor) private view {
        console.log("----------------------------------------");
        console.log("Verificando ator:", actorName);
        console.log("  - Endereco:", actor);
        console.log("  - Saldo:", actor.balance / 1e18, "ETH");
        console.log("----------------------------------------");
    }

    function _deployContract() private {
        _logBalance("Admin/Deployer", admin);
        vm.startBroadcast(ADMIN_PK);
        CofiCollection implementation = new CofiCollection();
        bytes memory data = abi.encodeWithSelector(
            CofiCollection.initialize.selector, admin, pauser, minter, admin, admin
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        collection = CofiCollection(address(proxy));
        vm.stopBroadcast();
        console.log("Contrato CofiCollection (Proxy) implantado em:", address(collection));
    }

    function _testAccessControl() private {
        console.log("\n--- 1. Testando Controle de Acesso ---");
        
        _logBalance("Admin", admin);
        vm.startBroadcast(ADMIN_PK);
        collection.grantRole(MINTER_ROLE, marketplace);
        vm.stopBroadcast();
        require(collection.hasRole(MINTER_ROLE, marketplace), "Falha ao delegar MINTER_ROLE");
        console.log("1.1 - Delegacao de Poder: OK");

        _logBalance("Minter", minter);
        bytes memory pauseCallData = abi.encodeWithSelector(collection.pause.selector);
        vm.prank(minter);
        (bool success, ) = address(collection).call(pauseCallData);
        require(!success, "Minter nao deveria poder pausar");

        _logBalance("Pauser", pauser);
        bytes memory mintCallData = abi.encodeWithSelector(collection.mint.selector, pCF1, 99, 1, "");
        vm.prank(pauser);
        (success, ) = address(collection).call(mintCallData);
        require(!success, "Pauser nao deveria poder mintar");
        
        console.log("1.2 - Separacao de Poderes: OK");
    }

    function _testAssetLifecycle() private {
        console.log("\n--- 2. Testando Ciclo de Vida do Ativo ---");
        uint256 tokenIdV1 = 1;
        uint256 tokenIdV2 = 2;

        _logBalance("Minter", minter);
        vm.startBroadcast(MINTER_PK);
        collection.mint(pCF1, tokenIdV1, 50, "");
        vm.stopBroadcast();
        console.log("2.1 - Criacao do Ativo (Mint): OK");

        _logBalance("pCF1", pCF1);
        vm.startBroadcast(PCF1_PK);
        collection.safeTransferFrom(pCF1, cCF1, tokenIdV1, 1, "");
        vm.stopBroadcast();
        console.log("2.2 - Transferencia Direta: OK");
        
        _logBalance("Minter", minter);
        vm.startBroadcast(MINTER_PK);
        collection.mint(pCF2, tokenIdV2, 100, "");
        vm.stopBroadcast();
        
        _logBalance("pCF2", pCF2);
        vm.startBroadcast(PCF2_PK);
        collection.setApprovalForAll(marketplace, true);
        vm.stopBroadcast();
        
        _logBalance("Marketplace", marketplace);
        vm.startBroadcast(MARKETPLACE_PK);
        collection.safeTransferFrom(pCF2, cCF2, tokenIdV2, 1, "");
        vm.stopBroadcast();
        console.log("2.3 - Transferencia via Marketplace: OK");

        _logBalance("cCF1", cCF1);
        vm.startBroadcast(CCF1_PK);
        collection.burn(cCF1, tokenIdV1, 1);
        vm.stopBroadcast();
        console.log("2.4 - Fim de Vida (Burn): OK");
    }

    function _testSecurityFeatures() private {
        console.log("\n--- 3. Testando Funcionalidades de Seguranca ---");
        uint256 tokenIdV1 = 1;

        _logBalance("Pauser", pauser);
        vm.startBroadcast(PAUSER_PK);
        collection.pause();
        vm.stopBroadcast();
        
        _logBalance("pCF1", pCF1);
        bytes memory transferCallData = abi.encodeWithSelector(collection.safeTransferFrom.selector, pCF1, cCF2, tokenIdV1, 1, "");
        vm.prank(pCF1);
        (bool success, ) = address(collection).call(transferCallData);
        require(!success, "Transferencia deveria falhar quando pausado");
        console.log("3.1 - Pausar Contrato: OK");

        _logBalance("Pauser", pauser);
        vm.startBroadcast(PAUSER_PK);
        collection.unpause();
        vm.stopBroadcast();

        _logBalance("pCF1", pCF1);
        vm.startBroadcast(PCF1_PK);
        collection.safeTransferFrom(pCF1, cCF1, tokenIdV1, 1, "");
        vm.stopBroadcast();
        console.log("3.2 - Retomar Operacoes (Unpause): OK");
    }
}