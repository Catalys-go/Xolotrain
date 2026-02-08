//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ScaffoldETHDeploy} from "./DeployHelpers.s.sol";
import {console} from "forge-std/console.sol";
import {AutoLpHelper} from "../contracts/AutoLpHelper.sol";
import {EggHatchHook} from "../contracts/EggHatchHook.sol";
import {PetRegistry} from "../contracts/PetRegistry.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

/**
 * @title DeployAll
 * @notice One-script deployment that handles hook mining and deployment in correct order
 * @dev This eliminates the need to manually mine hook addresses and pass them around
 * 
 * CREATE2_DEPLOYER:
 *   - In forge test: Use test contract address(this) or the pranking address
 *   - In forge script: Use 0x4e59b44847b379578588920cA78FbF26c0B4956C (CREATE2 Deployer Proxy)
 *   - This deployment uses CREATE2_DEPLOYER for deterministic hook addresses
 * 
 * Process:
 *   1. Deploy PetRegistry with deterministic salt
 *   2. Mine valid hook address using PetRegistry address
 *   3. Deploy EggHatchHook with mined salt
 *   4. Update poolKeys.json with mined hook address (manual step)
 *   5. Deploy AutoLpHelper (reads updated poolKeys.json)
 *   6. Initialize pools
 *   7. Connect contracts
 * 
 * Usage: yarn deploy (or forge script script/DeployAll.s.sol --broadcast)
 */
contract DeployAll is ScaffoldETHDeploy {
    using PoolIdLibrary for PoolKey;
    
    // CREATE2 Deployer Address - from "forge script" default deployer (0x4e59b44847b379578588920cA78FbF26c0B4956C)
    /* This is the address that will deploy the hook contract - add address you control for deployment on real chains */
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Deterministic salts for predictable addresses
    bytes32 constant REGISTRY_SALT = keccak256("PetRegistry.v1");
    
    function run() external ScaffoldEthDeployerRunner {
        console.log("====================================");
        console.log("Xolotrain Unified Deployment");
        console.log("====================================");
        console.log("");
        
        // Read pool configuration
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/addresses/poolKeys.json"));
        string memory prefix = string.concat(".", vm.toString(block.chainid));
        
        address poolManager = vm.parseJsonAddress(json, string.concat(prefix, ".poolManager"));
        address positionManager = vm.parseJsonAddress(json, string.concat(prefix, ".positionManager"));
        
        console.log("Chain ID:", block.chainid);
        console.log("Pool Manager:", poolManager);
        console.log("Position Manager:", positionManager);
        console.log("");
        
        // ===========================
        // STEP 1: Deploy PetRegistry
        // ===========================
        console.log("Step 1: Deploying PetRegistry...");
        PetRegistry petRegistry = new PetRegistry{salt: REGISTRY_SALT}(deployer);
        deployments.push(Deployment({name: "PetRegistry", addr: address(petRegistry)}));
        console.log("PetRegistry deployed at:", address(petRegistry));
        console.log("");
        
        // ===========================
        // STEP 2: Mine Hook Address
        // ===========================
        console.log("Step 2: Mining valid hook address...");
        console.log("This may take a minute...");
        
        // Hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG);
        
        // Mine a salt that will produce a hook address with the correct flags
        // IMPORTANT: Use CREATE2_DEPLOYER because Solidity's new{salt} uses msg.sender as deployer
        bytes memory constructorArgs = abi.encode(poolManager, address(petRegistry));
        
        (address hookAddress, bytes32 hookSalt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(EggHatchHook).creationCode,
            constructorArgs
        );
        
        console.log("SUCCESS! Mined hook address:", hookAddress);
        console.log("Salt:", vm.toString(hookSalt));
        console.log("");
        
        // ===========================
        // STEP 3: Deploy Hook
        // ===========================
        console.log("Step 3: Deploying EggHatchHook with mined salt...");
        EggHatchHook eggHatchHook = new EggHatchHook{salt: hookSalt}(poolManager, address(petRegistry));
        
        // Verify deployed address matches mined address
        require(address(eggHatchHook) == hookAddress, "Hook address mismatch!");
        deployments.push(Deployment({name: "EggHatchHook", addr: address(eggHatchHook)}));
        console.log("EggHatchHook deployed at:", address(eggHatchHook));
        console.log("");
        
        // ===========================
        // STEP 4: Read Pool Keys
        // ===========================
        console.log("Step 4: Reading pool configurations...");
        PoolKey memory ethUsdc = _readPoolKey(json, string.concat(prefix, ".ETH_USDC"));
        PoolKey memory ethUsdt = _readPoolKey(json, string.concat(prefix, ".ETH_USDT"));
        
        // IMPORTANT: USDC_USDT pool should use our mined hook address
        // This reads from poolKeys.json - update the file if hook address doesn't match
        PoolKey memory usdcUsdt = _readPoolKey(json, string.concat(prefix, ".USDC_USDT"));
        
        // Warn if hook address in poolKeys.json doesn't match deployed hook
        if (address(usdcUsdt.hooks) != hookAddress) {
            console.log("WARNING: poolKeys.json has different hook address!");
            console.log("  Expected:", hookAddress);
            console.log("  Found:", address(usdcUsdt.hooks));
            console.log("  Update poolKeys.json and redeploy, or continuing with mined address...");
            console.log("");
            
            // Override with mined hook address
            usdcUsdt.hooks = IHooks(hookAddress);
        }
        console.log("");
        
        // ===========================
        // STEP 5: Deploy AutoLpHelper
        // ===========================
        console.log("Step 5: Deploying AutoLpHelper...");
        bytes32 helperSalt = keccak256("AutoLpHelper.v1");
        AutoLpHelper autoLpHelper = new AutoLpHelper{salt: helperSalt}(
            IPoolManager(poolManager),
            IPositionManager(positionManager),
            ethUsdc,
            ethUsdt,
            usdcUsdt,
            usdcUsdt.tickSpacing,
            -6,
            6
        );
        deployments.push(Deployment({name: "AutoLpHelper", addr: address(autoLpHelper)}));
        console.log("AutoLpHelper deployed at:", address(autoLpHelper));
        console.log("");
        
        // ===========================
        // STEP 6: Connect Contracts
        // ===========================
        console.log("Step 6: Connecting contracts...");
        petRegistry.setHook(address(eggHatchHook));
        console.log("  PetRegistry.setHook()");
        
        autoLpHelper.setPetRegistry(address(petRegistry));
        console.log("  AutoLpHelper.setPetRegistry()");
        console.log("");
        
        // ===========================
        // STEP 7: Initialize USDC_USDT Pool
        // ===========================
        console.log("Step 7: Initializing USDC_USDT pool...");
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0); // 1:1 price
        
        try IPoolManager(poolManager).initialize(usdcUsdt, sqrtPriceX96) {
            console.log("  Pool initialized at 1:1 price");
        } catch {
            console.log("  Pool already initialized (skipping)");
        }
        console.log("");
        
        // Calculate USDC_USDT poolId for reference
        bytes32 calculatedPoolId = PoolId.unwrap(usdcUsdt.toId());
        
        // ===========================
        // SUMMARY
        // ===========================
        console.log("====================================");
        console.log("Deployment Complete!");
        console.log("====================================");
        console.log("PetRegistry:", address(petRegistry));
        console.log("EggHatchHook:", address(eggHatchHook));
        console.log("  Salt:", vm.toString(hookSalt));
        console.log("AutoLpHelper:", address(autoLpHelper));
        console.log("");
        console.log("USDC_USDT Pool ID:");
        console.logBytes32(calculatedPoolId);
        console.log("");
        console.log("====================================");
        console.log("Next Steps:");
        console.log("====================================");
        console.log("1. Update poolKeys.json USDC_USDT.hooks to:", hookAddress);
        console.log("   AND poolKeys.json USDC_USDT.poolId to:");
        console.logBytes32(calculatedPoolId);
        console.log("2. Run: node scripts-js/generateTsAbis.js");
        console.log("3. Set agent: cast send", address(petRegistry), '"setAgent(address)" $AGENT_ADDRESS');
        console.log("4. Add liquidity to ETH/USDC and ETH/USDT pools");
        console.log("5. Test with: cast send", address(autoLpHelper), '"swapEthToUsdcUsdtAndMint(uint128,uint128)" 1000000 1000000 --value 0.001ether');
        console.log("====================================");
    }
    
    /**
     * @notice Read PoolKey from JSON
     */
    function _readPoolKey(string memory json, string memory path) internal pure returns (PoolKey memory) {
        address token0 = vm.parseJsonAddress(json, string.concat(path, ".token0"));
        address token1 = vm.parseJsonAddress(json, string.concat(path, ".token1"));
        uint256 fee = vm.parseJsonUint(json, string.concat(path, ".fee"));
        uint256 spacing = vm.parseJsonUint(json, string.concat(path, ".tickSpacing"));
        address hooks = vm.parseJsonAddress(json, string.concat(path, ".hooks"));

        return PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: uint24(fee),
            tickSpacing: int24(int256(spacing)),
            hooks: IHooks(hooks)
        });
    }
}
