// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract ReadSlot0 is Script {
    function run() external {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/addresses/poolKeys.json"));
        string memory prefix = string.concat(".", vm.toString(block.chainid));
        address poolManager = vm.parseJsonAddress(json, string.concat(prefix, ".poolManager"));
        bytes32 poolId = vm.parseJsonBytes32(json, string.concat(prefix, ".USDC_USDT.poolId"));

        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) =
            StateLibrary.getSlot0(IPoolManager(poolManager), PoolId.wrap(poolId));
        console.logUint(uint256(sqrtPriceX96));
        console.logInt(tick);
        console.logUint(protocolFee);
        console.logUint(lpFee);
    }
}
