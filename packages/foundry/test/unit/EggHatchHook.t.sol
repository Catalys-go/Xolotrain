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

contract EggHatchHookTest is Test {
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
        
        // Set hook address in registry (PetRegistry uses address-based access)
        registry.setHook(address(hook));
        
        vm.stopPrank();
    }

    // ============ Hook Data Encoding Tests ============

    function testEncodeHookData() public pure {
        address owner = address(0x123);
        uint256 positionId = 42;
        
        bytes memory hookData = abi.encode(owner, positionId);
        
        (address decodedOwner, uint256 decodedPositionId) = abi.decode(hookData, (address, uint256));
        
        assertEq(decodedOwner, owner, "Owner should match");
        assertEq(decodedPositionId, positionId, "Position ID should match");
    }

    // ============ AfterAddLiquidity Tests ============

    function testAfterAddLiquidityHatchesPet() public {
        uint256 positionId = 1;
        uint256 petId = 0; // 0 = auto-derive deterministic pet ID
        bytes memory hookData = abi.encode(user1, petId, positionId, int24(-TICK_SPACING), int24(TICK_SPACING));
        
        // Simulate call from pool manager
        vm.startPrank(poolManager);
        
        // Before state - no pets
        assertEq(registry.totalSupply(), 0, "Should have no pets initially");
        
        // Call afterAddLiquidity
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -TICK_SPACING,
            tickUpper: TICK_SPACING,
            liquidityDelta: 1000,
            salt: bytes32(0)
        });
        
        hook.afterAddLiquidity(
            poolManager,
            poolKey,
            params,
            BalanceDelta.wrap(0),
            BalanceDelta.wrap(0),
            hookData
        );
        
        vm.stopPrank();
        
        // After state - pet should be hatched
        assertEq(registry.totalSupply(), 1, "Should have 1 pet after hatch");
        
        // Verify pet owner and data
        uint256 expectedPetId = _derivePetId(user1);
        PetRegistry.Pet memory pet = registry.getPet(expectedPetId);
        assertEq(pet.owner, user1, "User1 should own the pet");
        assertEq(pet.health, 100, "Initial health should be 100");
        assertEq(pet.chainId, block.chainid, "Chain ID should match");
        assertEq(pet.poolId, PoolId.unwrap(poolId), "Pool ID should match");
        assertEq(pet.positionId, positionId, "Position ID should match");
    }

    function testAfterAddLiquidityMultiplePets() public {
        vm.startPrank(poolManager);
        
        ModifyLiquidityParams memory params1 = ModifyLiquidityParams({
            tickLower: -TICK_SPACING,
            tickUpper: TICK_SPACING,
            liquidityDelta: 1000,
            salt: bytes32(0)
        });
        
        ModifyLiquidityParams memory params2 = ModifyLiquidityParams({
            tickLower: -TICK_SPACING * 2,
            tickUpper: TICK_SPACING * 2,
            liquidityDelta: 2000,
            salt: bytes32(0)
        });
        
        ModifyLiquidityParams memory params3 = ModifyLiquidityParams({
            tickLower: -TICK_SPACING,
            tickUpper: TICK_SPACING,
            liquidityDelta: 500,
            salt: bytes32(0)
        });
        
        // User1 creates first position - mints pet
        bytes memory hookData1 = abi.encode(user1, uint256(0), uint256(1), int24(-TICK_SPACING), int24(TICK_SPACING));
        hook.afterAddLiquidity(poolManager, poolKey, params1, BalanceDelta.wrap(0), BalanceDelta.wrap(0), hookData1);
        
        // User1 creates second position - updates SAME pet (idempotent)
        bytes memory hookData2 = abi.encode(user1, uint256(0), uint256(2), int24(-TICK_SPACING * 2), int24(TICK_SPACING * 2));
        hook.afterAddLiquidity(poolManager, poolKey, params2, BalanceDelta.wrap(0), BalanceDelta.wrap(0), hookData2);
        
        // User2 creates position - mints pet
        bytes memory hookData3 = abi.encode(user2, uint256(0), uint256(3), int24(-TICK_SPACING), int24(TICK_SPACING));
        hook.afterAddLiquidity(poolManager, poolKey, params3, BalanceDelta.wrap(0), BalanceDelta.wrap(0), hookData3);
        
        vm.stopPrank();
        
        // Verify total supply - 2 pets (one per user, not 3)
        assertEq(registry.totalSupply(), 2, "Should have 2 pets (one per user)");
        
        // Verify ownership - each user has ONE pet
        assertEq(registry.getPetsByOwner(user1).length, 1, "User1 should have 1 pet");
        assertEq(registry.getPetsByOwner(user2).length, 1, "User2 should have 1 pet");
        
        // Verify user1's pet was updated to latest position
        uint256 user1PetId = _derivePetId(user1);
        uint256 user2PetId = _derivePetId(user2);
        PetRegistry.Pet memory pet1 = registry.getPet(user1PetId);
        assertEq(pet1.positionId, 2, "Pet 1 should be updated to position 2 (latest)");
        
        // Verify user2's pet
        PetRegistry.Pet memory pet2 = registry.getPet(user2PetId);
        assertEq(pet2.positionId, 3, "Pet 2 position ID should be 3");
    }

    function testAfterAddLiquidityRevertsIfNotPoolManager() public {
        bytes memory hookData = abi.encode(user1, 1);
        
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -TICK_SPACING,
            tickUpper: TICK_SPACING,
            liquidityDelta: 1000,
            salt: bytes32(0)
        });
        
        // Try to call from non-pool-manager address
        vm.startPrank(user1);
        
        vm.expectRevert();
        hook.afterAddLiquidity(user1, poolKey, params, BalanceDelta.wrap(0), BalanceDelta.wrap(0), hookData);
        
        vm.stopPrank();
    }

    // ============ Immutable State Tests ============

    function testImmutablesSetCorrectly() public view {
        assertEq(address(hook.poolManager()), poolManager);
        assertEq(address(hook.REGISTRY()), address(registry));
        // Note: POOL_ID was removed in favor of dynamic poolId computation from PoolKey
    }
}
