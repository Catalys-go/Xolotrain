// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {ScaffoldETHDeploy} from "./DeployHelpers.s.sol";
import {EggHatchHook} from "../contracts/EggHatchHook.sol";

/**
 * @title DeployEggHatchHookDeterministic
 * @notice Deploys EggHatchHook to a deterministic address using CREATE2
 * @dev This ensures the hook address remains consistent across redeployments
 *      which is critical because hook addresses are part of Uniswap v4 PoolKeys
 */
contract DeployEggHatchHookDeterministic is ScaffoldETHDeploy {
    // Consistent salt for deterministic deployment
    // Change this if you need a different hook address
    bytes32 public constant DEPLOYMENT_SALT = keccak256("EggHatchHook.v1");
    
    function run(address petRegistryAddr) external ScaffoldEthDeployerRunner returns (EggHatchHook) {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/addresses/poolKeys.json"));
        string memory prefix = string.concat(".", vm.toString(block.chainid));
        
        address poolManager = vm.parseJsonAddress(json, string.concat(prefix, ".poolManager"));
        bytes32 poolId = vm.parseJsonBytes32(json, string.concat(prefix, ".USDC_USDT.poolId"));
        
        // Predict the deterministic address
        address predictedAddress = computeCreate2Address(
            DEPLOYMENT_SALT,
            keccak256(
                abi.encodePacked(
                    type(EggHatchHook).creationCode,
                    abi.encode(poolManager, petRegistryAddr, poolId)
                )
            )
        );
        
        console.logString("Predicted EggHatchHook address:");
        console.logAddress(predictedAddress);
        
        // Deploy using CREATE2
        EggHatchHook eggHatchHook = new EggHatchHook{salt: DEPLOYMENT_SALT}(
            poolManager,
            petRegistryAddr,
            poolId
        );
        
        require(address(eggHatchHook) == predictedAddress, "Address mismatch");
        
        console.logString("EggHatchHook deployed at (deterministic):");
        console.logAddress(address(eggHatchHook));
        vm.label(address(eggHatchHook), "EggHatchHook");

        deployments.push(Deployment({name: "EggHatchHook", addr: address(eggHatchHook)}));
        
        return eggHatchHook;
    }
    
    // Helper to compute CREATE2 address
    function computeCreate2Address(
        bytes32 salt,
        bytes32 initCodeHash
    ) internal view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this), // deployer
                            salt,
                            initCodeHash
                        )
                    )
                )
            )
        );
    }
}
