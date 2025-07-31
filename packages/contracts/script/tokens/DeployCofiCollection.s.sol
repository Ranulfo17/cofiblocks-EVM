// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {CofiCollection} from "src/tokens/CofiCollection.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployCofiCollection Script
 * @author CofiBlocks Team
 * @notice This script deploys the CofiCollection contract system, which includes an 
 * implementation contract and an ERC1967 proxy for upgradeability.
 * @dev It reads the deployer's private key from the .env file and assigns all initial
 * roles to the deployer account by default.
 */
contract DeployCofiCollection is Script {
    /**
     * @notice Executes the deployment sequence.
     * @return proxyAddress The address of the deployed ERC1967 proxy contract.
     */
    function run() public returns (address proxyAddress) {
        // Load the deployer private key from the .env file
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // By default, the deployer account will receive all roles.
        // This can be changed to different addresses if needed.
        address deployer = vm.addr(deployerPrivateKey);
        address defaultAdmin = deployer;
        address pauser = deployer;
        address minter = deployer;
        address uriSetter = deployer;
        address upgrader = deployer;

        console.log("Deploying with account:", defaultAdmin);
        console.log("Account balance:", defaultAdmin.balance / 1e18, "ETH");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the implementation contract (logic)
        CofiCollection implementation = new CofiCollection();
        console.log("Implementation contract deployed to:", address(implementation));

        // 2. Prepare the initializer function call
        bytes memory data = abi.encodeWithSelector(
            CofiCollection.initialize.selector,
            defaultAdmin,
            pauser,
            minter,
            uriSetter,
            upgrader
        );

        // 3. Deploy the ERC1967 proxy contract, pointing to the implementation
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        console.log("CofiCollection (Proxy) deployed to:", address(proxy));

        vm.stopBroadcast();
        
        return address(proxy);
    }
}