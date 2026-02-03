// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "./DeployHelpers.s.sol";
import {EggHatchHook} from "../contracts/EggHatchHook.sol";

contract DeployEggHatchHook is ScaffoldETHDeploy {
    // Deploy with default addresses, or override with custom ones
    function run() external ScaffoldEthDeployerRunner returns (EggHatchHook) {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/addresses/poolKeys.json"));
        string memory prefix = string.concat(".", vm.toString(block.chainid));
        
        address poolManager = vm.parseJsonAddress(json, string.concat(prefix, ".poolManager"));
        bytes32 poolId = vm.parseJsonBytes32(json, string.concat(prefix, ".USDC_USDT.poolId"));
        
        // Note: PetRegistry must be deployed first
        // You can either hardcode the address or read from deployments
        address petRegistryAddr = address(0); // Will be set after PetRegistry is deployed
        
        // For now, deploy with placeholder - will need to be updated
        console.logString("Warning: EggHatchHook deployed with address(0) for PetRegistry");
        console.logString("You must call this script after PetRegistry is deployed");
        
        EggHatchHook eggHatchHook = new EggHatchHook(poolManager, petRegistryAddr, poolId);
        
        console.logString("EggHatchHook deployed at:");
        console.logAddress(address(eggHatchHook));
        vm.label(address(eggHatchHook), "EggHatchHook");

        deployments.push(Deployment({name: "EggHatchHook", addr: address(eggHatchHook)}));
        
        return eggHatchHook;
    }
    
    // Alternative run method that takes PetRegistry address
    function run(address petRegistryAddr) external ScaffoldEthDeployerRunner returns (EggHatchHook) {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/addresses/poolKeys.json"));
        string memory prefix = string.concat(".", vm.toString(block.chainid));
        
        address poolManager = vm.parseJsonAddress(json, string.concat(prefix, ".poolManager"));
        bytes32 poolId = vm.parseJsonBytes32(json, string.concat(prefix, ".USDC_USDT.poolId"));
        
        EggHatchHook eggHatchHook = new EggHatchHook(poolManager, petRegistryAddr, poolId);
        
        console.logString("EggHatchHook deployed at:");
        console.logAddress(address(eggHatchHook));
        vm.label(address(eggHatchHook), "EggHatchHook");

        deployments.push(Deployment({name: "EggHatchHook", addr: address(eggHatchHook)}));
        
        return eggHatchHook;
    }
}
