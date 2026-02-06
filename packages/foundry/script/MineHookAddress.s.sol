// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {EggHatchHook} from "../contracts/EggHatchHook.sol";

/**
 * @title MineHookAddress
 * @notice Mines a valid CREATE2 salt for EggHatchHook deployment AND computes new poolIds
 * @dev Uniswap v4 hooks must have specific permission bits set in their address
 *      This script brute forces salts until finding one that produces a valid address,
 *      then computes the new poolIds for all pools that will use this hook
 * 
 * Usage:
 *   forge script script/MineHookAddress.s.sol --sig "run(address,address,uint256)" <poolManager> <petRegistry> <chainId>
 * 
 * Example:
 *   forge script script/MineHookAddress.s.sol --sig "run(address,address,uint256)" \
 *     0x000000000004444c5dc75cB358380D2e3dE08A90 \
 *     0xb288315b51e6fac212513e1a7c70232fa584bbb9 \
 *     31337
 */
contract MineHookAddress is Script {
    using PoolIdLibrary for PoolKey;
    // Permission flags we need for EggHatchHook
    // We only use afterAddLiquidity, so we need that bit set
    uint160 constant FLAGS = uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG);
    
    // Mask to extract the lower 14 bits (permission bits)
    uint160 constant FLAG_MASK = 0x3FFF; // 0b11111111111111
    
    // CREATE2 Deployer Proxy used by Foundry scripts
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Maximum iterations to prevent infinite loops
    uint256 constant MAX_ITERATIONS = 100_000;

    function run(address poolManager, address petRegistry, uint256 chainId) external {
        run(poolManager, petRegistry, chainId, address(0));
    }

    function run(address poolManager, address petRegistry, uint256 chainId, address specifiedDeployer) public {
        console.log("===========================================");
        console.log("Mining Hook Address for EggHatchHook");
        console.log("===========================================");
        console.log("Pool Manager:", poolManager);
        console.log("Pet Registry:", petRegistry);
        console.log("Chain ID:", chainId);
        console.log("Required Flags:", FLAGS);
        console.log("");
        console.log("Mining... this may take a minute...");
        console.log("");

        bytes memory creationCode = type(EggHatchHook).creationCode;
        bytes memory constructorArgs = abi.encode(poolManager, petRegistry);
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        
        // Always use CREATE2_DEPLOYER (Foundry's CREATE2 proxy)
        console.log("Using CREATE2 Deployer:", CREATE2_DEPLOYER);
        
        (address hookAddress, bytes32 salt) = mineSalt(CREATE2_DEPLOYER, bytecode);
        
        console.log("===========================================");
        console.log("SUCCESS! Valid hook address found:");
        console.log("===========================================");
        console.log("Hook Address:", hookAddress);
        console.log("Salt:", vm.toString(salt));
        console.log("");
        console.log("Verification:");
        console.log("Address & FLAG_MASK:", uint160(hookAddress) & FLAG_MASK);
        console.log("Expected FLAGS:", FLAGS);
        console.log("Match:", (uint160(hookAddress) & FLAG_MASK) == (FLAGS & FLAG_MASK));
        console.log("");
        
        // Compute new poolId for USDC_USDT (the only pool that uses our hook)
        console.log("===========================================");
        console.log("Computing Pool ID for USDC_USDT with hook:");
        console.log("===========================================");
        console.log("NOTE: ETH_USDC and ETH_USDT are existing pools without hooks");
        console.log("");
        
        // Read pool configurations from JSON based on chainId
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/addresses/poolKeys.json"));
        string memory prefix = string.concat(".", vm.toString(chainId));
        
        // Only get USDC_USDT configuration (the pool we're creating with our hook)
        address usdcUsdtToken0 = vm.parseJsonAddress(json, string.concat(prefix, ".USDC_USDT.token0"));
        address usdcUsdtToken1 = vm.parseJsonAddress(json, string.concat(prefix, ".USDC_USDT.token1"));
        uint24 usdcUsdtFee = uint24(vm.parseJsonUint(json, string.concat(prefix, ".USDC_USDT.fee")));
        int24 usdcUsdtSpacing = int24(int256(vm.parseJsonUint(json, string.concat(prefix, ".USDC_USDT.tickSpacing"))));
        
        // Create PoolKey for USDC_USDT with new hook address
        PoolKey memory usdcUsdtKey = PoolKey({
            currency0: Currency.wrap(usdcUsdtToken0),
            currency1: Currency.wrap(usdcUsdtToken1),
            fee: usdcUsdtFee,
            tickSpacing: usdcUsdtSpacing,
            hooks: IHooks(hookAddress)
        });
        
        // Compute poolId
        bytes32 usdcUsdtPoolId = PoolId.unwrap(usdcUsdtKey.toId());
        
        console.log("USDC_USDT poolId:", vm.toString(usdcUsdtPoolId));
        console.log("");
        
        console.log("===========================================");
        console.log("Next Steps:");
        console.log("===========================================");
        console.log("1. Update Deploy.s.sol to use this salt:");
        console.log("   bytes32 hookSalt =", vm.toString(salt), ";");
        console.log("");
        console.log("2. Update poolKeys.json for chain", chainId, ":");
        console.log("   USDC_USDT pool only:");
        console.log("   \"hooks\":", vm.toString(hookAddress));
        console.log("   \"poolId\":", vm.toString(usdcUsdtPoolId));
        console.log("");
        console.log("   (ETH_USDC and ETH_USDT keep hooks = 0x0000... and existing poolIds)");
        console.log("");
        console.log("3. Redeploy contracts with: yarn deploy --reset");
        console.log("===========================================");
    }

    function mineSalt(address deployer, bytes memory bytecode) internal pure returns (address, bytes32) {
        bytes32 bytecodeHash = keccak256(bytecode);
        
        for (uint256 i = 0; i < MAX_ITERATIONS; i++) {
            bytes32 salt = bytes32(i);
            
            // Compute CREATE2 address
            address predictedAddress = computeCreate2Address(deployer, salt, bytecodeHash);
            
            // Check if address has correct permission bits
            if ((uint160(predictedAddress) & FLAG_MASK) == (FLAGS & FLAG_MASK)) {
                return (predictedAddress, salt);
            }
            
            // Log progress every 10k iterations
            if (i % 10000 == 0 && i > 0) {
                console.log("Checked", i, "salts...");
            }
        }
        
        revert("Failed to find valid salt within MAX_ITERATIONS");
    }

    function computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 bytecodeHash
    ) internal pure returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                deployer,
                salt,
                bytecodeHash
            )
        );
        return address(uint160(uint256(hash)));
    }
}
