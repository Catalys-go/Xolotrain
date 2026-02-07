// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

interface IPetRegistry {
    function hatchFromHook(
        address owner,
        uint256 petId,
        uint256 chainId,
        bytes32 poolId,
        uint256 positionId
    ) external returns (uint256);
}

/**
 * @title EggHatchHook
 * @notice Uniswap v4 hook that mints pet NFTs when users add liquidity to USDC/USDT pool
 * @dev Extends BaseHook following Uniswap v4 best practices
 */
contract EggHatchHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    
    IPetRegistry public immutable REGISTRY;

    error InvalidOwner();
    error InvalidPositionId();

    constructor(address _poolManager, address _registry) BaseHook(IPoolManager(_poolManager)) {
        REGISTRY = IPetRegistry(_registry);
    }

    /**
     * @notice Declare which hook functions are implemented
     * @dev Only afterAddLiquidity is used - this ensures the hook address has correct permission bits
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,  // ✅ Only this hook is used
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

    /**
     * @notice Hook called after liquidity is added to the pool
     * @dev Mints or updates a pet NFT for the LP position owner
     * @param key The pool key
     * @param hookData Encoded data: abi.encode(owner, petId, positionId, tickLower, tickUpper)
     */
    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        // Compute poolId from the PoolKey
        bytes32 poolId = PoolId.unwrap(key.toId());
        
        // Decode hookData
        // Schema: abi.encode(owner, petId, positionId, tickLower, tickUpper)
        // - owner: Address of the LP position owner (must be valid)
        // - petId: Pet ID (0 for auto-derive/initial hatch, >0 for explicit migration)
        // - positionId: Unique ID for the LP position (must be non-zero)
        // - tickLower: Lower tick boundary of the LP range (informational)
        // - tickUpper: Upper tick boundary of the LP range (informational)
        // Encoded in: AutoLpHelper.unlockCallback()
        (address owner, uint256 petId, uint256 positionId,,) = abi.decode(hookData, (address, uint256, uint256, int24, int24));
        
        // Validate hookData
        if (owner == address(0)) revert InvalidOwner();
        if (positionId == 0) revert InvalidPositionId();
        
        // Pass petId to registry:
        // - petId = 0: Auto-derive deterministic ID (initial hatch)
        // - petId > 0: Use explicit ID (cross-chain migration)
        REGISTRY.hatchFromHook(owner, petId, block.chainid, poolId, positionId);

        return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }
}