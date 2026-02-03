// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

contract VerifyPools is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    function run() external view {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/addresses/poolKeys.json"));
        string memory prefix = string.concat(".", vm.toString(block.chainid));

        address poolManager = vm.parseJsonAddress(json, string.concat(prefix, ".poolManager"));
        IPoolManager pm = IPoolManager(poolManager);

        console.log("=== Verifying Pools on Chain", block.chainid, "===");
        console.log("PoolManager:", poolManager);
        console.log("");

        // ETH_USDC
        PoolKey memory ethUsdc = _readPoolKey(json, string.concat(prefix, ".ETH_USDC"));
        _verifyPool(pm, ethUsdc, "ETH_USDC");

        // ETH_USDT
        PoolKey memory ethUsdt = _readPoolKey(json, string.concat(prefix, ".ETH_USDT"));
        _verifyPool(pm, ethUsdt, "ETH_USDT");

        // USDC_USDT
        PoolKey memory usdcUsdt = _readPoolKey(json, string.concat(prefix, ".USDC_USDT"));
        _verifyPool(pm, usdcUsdt, "USDC_USDT");
    }

    function _verifyPool(IPoolManager pm, PoolKey memory key, string memory name) internal view {
        console.log("--- Pool:", name);
        console.log("  Currency0:", Currency.unwrap(key.currency0));
        console.log("  Currency1:", Currency.unwrap(key.currency1));
        console.log("  Fee:", key.fee);
        console.log("  TickSpacing:", uint256(int256(key.tickSpacing)));
        console.log("  Hooks:", address(key.hooks));

        PoolId poolId = key.toId();
        console.log("  Calculated PoolId:");
        console.logBytes32(PoolId.unwrap(poolId));

        try pm.getSlot0(poolId) returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) {
            console.log("  Pool exists!");
            console.log("  sqrtPriceX96:", sqrtPriceX96);
            console.log("  tick:", uint256(int256(tick)));
            console.log("  lpFee:", lpFee);
        } catch {
            console.log("  Pool does NOT exist or getSlot0 failed");
        }
        console.log("");
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
