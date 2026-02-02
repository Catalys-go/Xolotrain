// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IHooks} from "uniswap-v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "uniswap-v4-core/src/interfaces/IPoolManager.sol";

interface IPetRegistry {
    function hatchFromHook(
        address owner,
        uint256 chainId,
        bytes32 poolId,
        uint256 positionId
    ) external returns (uint256);
}

contract PetHatchHook is IHooks {
    address public immutable poolManager;
    IPetRegistry public immutable registry;
    bytes32 public immutable poolId;

    constructor(address _poolManager, address _registry, bytes32 _poolId) {
        poolManager = _poolManager;
        registry = IPetRegistry(_registry);
        poolId = _poolId;
    }

    // This signature must match the v4 hook interface you use.
    // Example name: afterAddLiquidity
    function afterAddLiquidity(
        /* PoolKey */ bytes32 /*key*/,
        /* ModifyLiquidityParams */ bytes32 /*params*/,
        /* BalanceDelta */ int256 /*delta*/,
        bytes calldata hookData
    ) external returns (bytes4) {
        require(msg.sender == poolManager, "only manager");

        // Decode the LP owner + positionId from hookData
        (address owner, uint256 positionId) = abi.decode(hookData, (address, uint256));

        // On-chain hatch triggered by liquidity add
        registry.hatchFromHook(owner, block.chainid, poolId, positionId);

        // Return the hook selector for success
        return this.afterAddLiquidity.selector;
    }
}