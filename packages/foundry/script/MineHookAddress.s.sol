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
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {EggHatchHook} from "../contracts/EggHatchHook.sol";

/**
 * @title MineHookAddress
 * @notice Mines a valid CREATE2 salt for EggHatchHook deployment using Uniswap's official HookMiner
 * @dev Follows Uniswap v4 best practices: https://docs.uniswap.org/contracts/v4/guides/hooks/hook-deployment
 * 
 * CREATE2_DEPLOYER:
 *   - In forge test: Use test contract address(this) or the pranking address
 *   - In forge script: Use 0x4e59b44847b379578588920cA78FbF26c0B4956C (CREATE2 Deployer Proxy)
 *   - Alternative: Could use scaffold-eth deployer account (msg.sender during broadcast)
 * 
 * Usage:
 *   forge script script/MineHookAddress.s.sol --sig "run(address,address,uint256)" <poolManager> <petRegistry> <chainId>
 * 
 * Example:
 *   forge script script/MineHookAddress.s.sol --sig "run(address,address,uint256)" \
 *     0x000000000004444c5dc75cB358380D2e3dE08A90 \
 *     0xB288315B51e6FAc212513E1a7C70232fa584Bbb9 \
 *     31337
 */
contract MineHookAddress is Script {
    using PoolIdLibrary for PoolKey;
    
    // CREATE2 Deployer Address - from "forge script" default deployer (0x4e59b44847b379578588920cA78FbF26c0B4956C)
    /* This is the address that will deploy the hook contract - add address you control for deployment on real chains */
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;


    function run(address poolManager, address petRegistry, uint256 chainId) external {
        console.log("===========================================");
        console.log("Mining Hook Address for EggHatchHook");
        console.log("===========================================");
        console.log("Pool Manager:", poolManager);
        console.log("Pet Registry:", petRegistry);
        console.log("Chain ID:", chainId);
        console.log("");
        console.log("Mining... this may take a minute...");
        console.log("");

        // Hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG);
        
        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(poolManager, petRegistry);
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(EggHatchHook).creationCode,
            constructorArgs
        );
        
        console.log("===========================================");
        console.log("SUCCESS:");
        console.log("Hook Address:", hookAddress);
        console.log("Salt:", uint256(salt));
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
}

