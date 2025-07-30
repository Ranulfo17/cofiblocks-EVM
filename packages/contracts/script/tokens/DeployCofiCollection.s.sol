// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {CofiCollection} from "src/tokens/CofiCollection.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployCofiCollection is Script {
    function run() public returns (address) {
        // Carrega as variáveis de ambiente do arquivo .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Define os endereços para os papéis.
        // Por padrão, a conta deployer receberá todos os papéis.
        // Você pode alterar isso para endereços diferentes se necessário.
        address deployer = vm.addr(deployerPrivateKey);
        address defaultAdmin = deployer;
        address pauser = deployer;
        address minter = deployer;
        address uriSetter = deployer;
        address upgrader = deployer;

        console.log("Iniciando deploy com a conta:", defaultAdmin);
        console.log("Saldo da conta:", defaultAdmin.balance / 1e18, "ETH");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Implanta o contrato de implementação (lógica)
        CofiCollection implementation = new CofiCollection();
        console.log("Contrato de implementacao implantado em:", address(implementation));

        // 2. Prepara a chamada de inicialização
        bytes memory data = abi.encodeWithSelector(
            CofiCollection.initialize.selector,
            defaultAdmin,
            pauser,
            minter,
            uriSetter,
            upgrader
        );

        // 3. Implanta o contrato de Proxy apontando para a implementação
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        console.log("Contrato CofiCollection (Proxy) implantado em:", address(proxy));

        vm.stopBroadcast();
        
        return address(proxy);
    }
}