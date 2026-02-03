// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {console} from "forge-std/console.sol";
import {ScaffoldETHDeploy} from "./DeployHelpers.s.sol";
import {PetRegistry} from "../contracts/PetRegistry.sol";

contract DeployPetRegistry is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        PetRegistry petRegistry = new PetRegistry();
        
        console.logString("PetRegistry deployed at:");
        console.logAddress(address(petRegistry));
        vm.label(address(petRegistry), "PetRegistry");

        deployments.push(Deployment({name: "PetRegistry", addr: address(petRegistry)}));
    }
}
