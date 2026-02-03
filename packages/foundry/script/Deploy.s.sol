//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { DeployAutoLpHelper } from "./DeployAutoLpHelper.s.sol";
import { DeployPetRegistry } from "./DeployPetRegistry.s.sol";
import { DeployEggHatchHook } from "./DeployEggHatchHook.s.sol";

/**
 * @notice Main deployment script for all contracts
 * @dev Run this when you want to deploy multiple contracts at once
 *
 * Example: yarn deploy # runs this script(without`--file` flag)
 */
contract DeployScript is ScaffoldETHDeploy {
    function run() external {
        // Deploy contracts in proper order (dependencies first)
        
        // 1. Deploy AutoLpHelper (standalone)
        DeployAutoLpHelper deployAutoLpHelper = new DeployAutoLpHelper();
        deployAutoLpHelper.run();

        // 2. Deploy PetRegistry (no dependencies)
        DeployPetRegistry deployPetRegistry = new DeployPetRegistry();
        deployPetRegistry.run();

        // 3. Deploy EggHatchHook (needs PetRegistry address)
        // Note: This won't properly link to PetRegistry since it's deployed in separate script
        // For full integration, you need to deploy these individually:
        // yarn deploy --file DeployAutoLpHelper.s.sol
        // yarn deploy --file DeployPetRegistry.s.sol
        // yarn deploy --file DeployEggHatchHook.s.sol
        
        console.logString("All contracts deployed!");
        console.logString("Note: EggHatchHook will need manual linking to PetRegistry via setHook()");
    }
}
