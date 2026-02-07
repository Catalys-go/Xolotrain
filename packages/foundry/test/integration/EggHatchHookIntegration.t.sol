// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {EggHatchHook} from "../../contracts/EggHatchHook.sol";
import {PetRegistry} from "../../contracts/PetRegistry.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

contract EggHatchHookIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;
    
    EggHatchHook public hook;
    PetRegistry public registry;
    
    address public deployer = address(0x1);
    address public poolManager = address(0x999); // Mock pool manager address
    address public user1 = address(0x100);
    address public user2 = address(0x200);
    
    Currency public currency0 = Currency.wrap(address(0x1000));
    Currency public currency1 = Currency.wrap(address(0x2000));
    uint24 public constant FEE = 3000;
    int24 public constant TICK_SPACING = 60;
    
    PoolKey public poolKey;
    PoolId public poolId;
    
    /// @notice Helper to calculate deterministic pet ID (matches PetRegistry logic)
    function _derivePetId(address petOwner) internal pure returns (uint256) {
        return uint256(uint48(bytes6(keccak256(abi.encodePacked("XolotrainPet", petOwner)))));
    }

    function setUp() public {
        vm.startPrank(deployer);
        
        // Deploy registry first (deployer is owner)
        registry = new PetRegistry(deployer);
        
        // Mine a valid hook address with CREATE2
        uint160 flags = uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG);
        bytes memory constructorArgs = abi.encode(poolManager, address(registry));
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployer, // deployer will use CREATE2
            flags,
            type(EggHatchHook).creationCode,
            constructorArgs
        );
        
        // Deploy hook at the mined address using CREATE2 with the salt
        hook = new EggHatchHook{salt: salt}(
            poolManager,
            address(registry)
        );
        
        // Verify the hook deployed at the expected address
        require(address(hook) == hookAddress, "Hook address mismatch");
        
        // Create pool key with the hook
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        
        poolId = poolKey.toId();
        
        // Set hook address in registry
        registry.setHook(address(hook));
        
        vm.stopPrank();
    }

    // ============ Integration Tests ============

    function testFullHatchFlow() public {
        // Setup: User1 wants to create LP and hatch pet
        uint256 positionId = 42;
        uint256 petId = 0; // Auto-derive deterministic pet ID
        int24 tickLower = -120;
        int24 tickUpper = 120;
        bytes memory hookData = abi.encode(user1, petId, positionId, tickLower, tickUpper);
        
        // Verify initial state
        assertEq(registry.totalSupply(), 0);
        uint256 expectedPetId = _derivePetId(user1);
        assertFalse(registry.exists(expectedPetId));
        
        // Simulate pool manager calling afterAddLiquidity
        vm.startPrank(poolManager);
        
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 100000,
            salt: bytes32(0)
        });
        
        (bytes4 selector,) = hook.afterAddLiquidity(
            poolManager,
            poolKey,
            params,
            BalanceDelta.wrap(0),
            BalanceDelta.wrap(0),
            hookData
        );
        
        vm.stopPrank();
        
        // Verify hook returned correct selector
        assertEq(selector, IHooks.afterAddLiquidity.selector);
        
        // Verify pet was created
        assertTrue(registry.exists(expectedPetId), "Pet should exist");
        assertEq(registry.totalSupply(), 1, "Should have 1 pet");
        
        // Verify pet details
        PetRegistry.Pet memory pet = registry.getPet(expectedPetId);
        assertEq(pet.owner, user1, "User1 should own pet");
        assertEq(pet.health, 100);
        assertEq(pet.lastUpdate, block.timestamp);
        assertEq(pet.chainId, block.chainid);
        assertEq(pet.poolId, PoolId.unwrap(poolId));
        assertEq(pet.positionId, positionId);
    }

    function testHookDataWithDifferentPositionIds() public {
        vm.startPrank(poolManager);
        
        int24 tickLower = -TICK_SPACING;
        int24 tickUpper = TICK_SPACING;
        
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 1000,
            salt: bytes32(0)
        });
        
        // User1 creates multiple positions - all update SAME pet (idempotent)
        for (uint256 i = 1; i <= 5; i++) {
            bytes memory hookData = abi.encode(user1, uint256(0), i * 100, tickLower, tickUpper); // Position IDs: 100, 200, 300, 400, 500, petId=0
            
            hook.afterAddLiquidity(
                poolManager,
                poolKey,
                params,
                BalanceDelta.wrap(0),
                BalanceDelta.wrap(0),
                hookData
            );
        }
        
        vm.stopPrank();
        
        // Verify only ONE pet exists (idempotent behavior)
        assertEq(registry.totalSupply(), 1, "Should have 1 pet (idempotent)");
        
        // Verify pet has latest position ID
        uint256 expectedPetId = _derivePetId(user1);
        PetRegistry.Pet memory pet = registry.getPet(expectedPetId);
        assertEq(pet.positionId, 500, "Pet should have latest position ID");
    }
}
