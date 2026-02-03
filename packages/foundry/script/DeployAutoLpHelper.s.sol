// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "./DeployHelpers.s.sol";
import {AutoLpHelper} from "../contracts/AutoLpHelper.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract DeployAutoLpHelper is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/addresses/poolKeys.json"));
        string memory prefix = string.concat(".", vm.toString(block.chainid));

        PoolKey memory ethUsdc = _readPoolKey(json, string.concat(prefix, ".ETH_USDC"));
        PoolKey memory ethUsdt = _readPoolKey(json, string.concat(prefix, ".ETH_USDT"));
        PoolKey memory usdcUsdt = _readPoolKey(json, string.concat(prefix, ".USDC_USDT"));
        address poolManager = vm.parseJsonAddress(json, string.concat(prefix, ".poolManager"));

        address weth = Currency.unwrap(ethUsdt.currency0);

        AutoLpHelper helper = new AutoLpHelper(
            IPoolManager(poolManager),
            ethUsdc,
            ethUsdt,
            usdcUsdt,
            weth,
            usdcUsdt.tickSpacing,
            -6,
            6
        );

        deployments.push(Deployment({name: "AutoLpHelper", addr: address(helper)}));
    }

    function _readPoolKey(string memory json, string memory path) internal returns (PoolKey memory) {
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
