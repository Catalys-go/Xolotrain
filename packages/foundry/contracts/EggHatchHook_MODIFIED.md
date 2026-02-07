// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

// ✅ MODIFIED: Added petId parameter
interface IPetRegistry {
    function hatchFromHook(
        address owner,
        uint256 petId,    // ✅ NEW
        uint256 chainId,
        bytes32 poolId,
        uint256 positionId
    ) external returns (uint256);
}

contract EggHatchHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    
    IPetRegistry public immutable REGISTRY;
    
    error InvalidOwner();
    error InvalidPositionId();
    
    constructor(address _poolManager, address _registry) BaseHook(IPoolManager(_poolManager)) {
        REGISTRY = IPetRegistry(_registry);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ✅ MODIFIED: Decode 5 fields
    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        bytes32 poolId = PoolId.unwrap(key.toId());
        
        (address owner, uint256 petId, uint256 positionId,,) = 
            abi.decode(hookData, (address, uint256, uint256, int24, int24));
        
        if (owner == address(0)) revert InvalidOwner();
        if (positionId == 0) revert InvalidPositionId();
        
        REGISTRY.hatchFromHook(owner, petId, block.chainid, poolId, positionId);
        
        return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }
}
