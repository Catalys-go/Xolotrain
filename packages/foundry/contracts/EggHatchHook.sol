// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

interface IPetRegistry {
    function hatchFromHook(
        address owner,
        uint256 chainId,
        bytes32 poolId,
        uint256 positionId
    ) external returns (uint256);
}

contract EggHatchHook is IHooks {
    using PoolIdLibrary for PoolKey;
    
    address public immutable POOL_MANAGER;
    IPetRegistry public immutable REGISTRY;

    error OnlyPoolManager(address caller);
    error InvalidOwner();
    error InvalidPositionId();

    constructor(address _poolManager, address _registry) {
        POOL_MANAGER = _poolManager;
        REGISTRY = IPetRegistry(_registry);
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) external returns (bytes4, BalanceDelta) {
        if (msg.sender != POOL_MANAGER) revert OnlyPoolManager(msg.sender);

        // Compute poolId from the PoolKey
        bytes32 poolId = PoolId.unwrap(key.toId());
        
        // Decode hookData
        // Schema: abi.encode(owner, positionId, tickLower, tickUpper)
        // - owner: Address of the LP position owner (must be valid)
        // - positionId: Unique ID for the LP position (must be non-zero)
        // - tickLower: Lower tick boundary of the LP range (informational)
        // - tickUpper: Upper tick boundary of the LP range (informational)
        // Encoded in: AutoLpHelper.unlockCallback()
        (address owner, uint256 positionId,,) = abi.decode(hookData, (address, uint256, int24, int24));
        
        // Validate hookData
        if (owner == address(0)) revert InvalidOwner();
        if (positionId == 0) revert InvalidPositionId();
        
        // Note: PetRegistry enforces 1 pet per user constraint
        // If user already has a pet, it updates the existing pet instead of creating duplicate
        REGISTRY.hatchFromHook(owner, block.chainid, poolId, positionId);

        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function beforeSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        bytes calldata
    ) external pure returns (bytes4, BeforeSwapDelta, uint24) {
        return (IHooks.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }

    function afterSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, int128) {
        return (IHooks.afterSwap.selector, 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IHooks.afterDonate.selector;
    }
}