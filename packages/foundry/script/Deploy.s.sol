//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ScaffoldETHDeploy} from "./DeployHelpers.s.sol";
import {console} from "forge-std/console.sol";
import {AutoLpHelper} from "../contracts/AutoLpHelper.sol";
import {EggHatchHook} from "../contracts/EggHatchHook.sol";
import {PetRegistry} from "../contracts/PetRegistry.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Main deployment script for all contracts
 * @dev Run this when you want to deploy multiple contracts at once
 *
 * Example: yarn deploy # runs this script(without`--file` flag)
 */
contract DeployScript is ScaffoldETHDeploy {
    using PoolIdLibrary for PoolKey;
    
    function run() external ScaffoldEthDeployerRunner {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/addresses/poolKeys.json"));
        string memory prefix = string.concat(".", vm.toString(block.chainid));

        PoolKey memory ethUsdc = _readPoolKey(json, string.concat(prefix, ".ETH_USDC"));
        PoolKey memory ethUsdt = _readPoolKey(json, string.concat(prefix, ".ETH_USDT"));
        PoolKey memory usdcUsdt = _readPoolKey(json, string.concat(prefix, ".USDC_USDT"));
        address positionManager = vm.parseJsonAddress(json, string.concat(prefix, ".positionManager"));
        address poolManager = vm.parseJsonAddress(json, string.concat(prefix, ".poolManager"));

        // 1) Deploy AutoLpHelper (deterministic via CREATE2)
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

        // 2) Deploy PetRegistry (deterministic via CREATE2)
        bytes32 registrySalt = keccak256("PetRegistry.v1");
        PetRegistry petRegistry = new PetRegistry{salt: registrySalt}(deployer);
        deployments.push(Deployment({name: "PetRegistry", addr: address(petRegistry)}));

        // 3) Deploy EggHatchHook (deterministic via CREATE2)
        // Note: poolId is now computed dynamically from PoolKey in the hook
        bytes32 hookSalt = 0x00000000000000000000000000000000000000000000000000000000000002d8;
        EggHatchHook eggHatchHook = new EggHatchHook{salt: hookSalt}(address(poolManager), address(petRegistry));
        deployments.push(Deployment({name: "EggHatchHook", addr: address(eggHatchHook)}));
        petRegistry.setHook(address(eggHatchHook));

        // 4) Initialize USDC_USDT pool at 1:1 price (tick 0)
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);
        try IPoolManager(poolManager).initialize(usdcUsdt, sqrtPriceX96) {
            console.logString("USDC_USDT pool initialized successfully at 1:1 price");
        } catch {
            console.logString("USDC_USDT pool already initialized (skipping)");
        }

        console.logString("All contracts deployed and exported!");
        console.logString("AutoLpHelper:");
        console.logAddress(address(autoLpHelper));
        console.logString("PetRegistry:");
        console.logAddress(address(petRegistry));
        console.logString("EggHatchHook:");
        console.logAddress(address(eggHatchHook));
    }

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
