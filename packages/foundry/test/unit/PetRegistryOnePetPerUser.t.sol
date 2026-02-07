// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PetRegistry} from "../../contracts/PetRegistry.sol";

/**
 * @title PetRegistryOnePetPerUser
 * @notice Tests to verify the "1 pet per user" constraint and position update behavior
 * @dev Key Behavior: When a user creates multiple LP positions, their pet is UPDATED (not duplicated)
 *      This means the pet always tracks the user's LATEST position, and old positions are abandoned.
 */
contract PetRegistryOnePetPerUserTest is Test {
    PetRegistry public registry;
    
    address public owner = address(0x1);
    address public hook = address(0x2);
    address public user1 = address(0x100);
    address public user2 = address(0x200);
    
    bytes32 public poolId1 = bytes32(uint256(0x1111));
    bytes32 public poolId2 = bytes32(uint256(0x2222));
    
    function setUp() public {
        vm.startPrank(owner);
        registry = new PetRegistry(owner);
        registry.setHook(hook);
        vm.stopPrank();
    }

    // ============ 1 Pet Per User Constraint Tests ============

    function testUserCanOnlyHaveOnePet() public {
        vm.startPrank(hook);
        
        // User1 creates first position - mints pet #1
        uint256 petId1 = registry.hatchFromHook(user1, block.chainid, poolId1, 100);
        assertEq(petId1, 1, "First pet should have ID 1");
        
        // User1 creates second position - UPDATES pet #1 (not creates pet #2)
        uint256 petId2 = registry.hatchFromHook(user1, block.chainid, poolId1, 200);
        assertEq(petId2, 1, "Second call should return SAME pet ID");
        
        // Verify only 1 pet exists
        assertEq(registry.totalSupply(), 1, "User should have exactly 1 pet");
        
        // Verify pet has latest position data
        PetRegistry.Pet memory pet = registry.getPet(1);
        assertEq(pet.positionId, 200, "Pet should track latest position (200)");
        assertEq(pet.owner, user1, "Pet should still belong to user1");
        
        vm.stopPrank();
    }

    function testMultipleUsersCanEachHaveOnePet() public {
        vm.startPrank(hook);
        
        // User1 creates position - pet #1
        uint256 user1PetId = registry.hatchFromHook(user1, block.chainid, poolId1, 100);
        
        // User2 creates position - pet #2
        uint256 user2PetId = registry.hatchFromHook(user2, block.chainid, poolId1, 200);
        
        // Verify both pets exist
        assertEq(registry.totalSupply(), 2, "Should have 2 pets (one per user)");
        assertEq(user1PetId, 1, "User1 pet ID");
        assertEq(user2PetId, 2, "User2 pet ID");
        
        // Verify ownership
        PetRegistry.Pet memory pet1 = registry.getPet(1);
        PetRegistry.Pet memory pet2 = registry.getPet(2);
        assertEq(pet1.owner, user1);
        assertEq(pet2.owner, user2);
        
        vm.stopPrank();
    }

    function testUserCreatingThreePositionsOnlyHasOnePet() public {
        vm.startPrank(hook);
        
        // User1 creates 3 positions sequentially
        uint256 petId1 = registry.hatchFromHook(user1, block.chainid, poolId1, 100);
        uint256 petId2 = registry.hatchFromHook(user1, block.chainid, poolId1, 200);
        uint256 petId3 = registry.hatchFromHook(user1, block.chainid, poolId1, 300);
        
        // All should return same pet ID
        assertEq(petId1, petId2, "Second position should return same pet ID");
        assertEq(petId2, petId3, "Third position should return same pet ID");
        
        // Only 1 pet should exist
        assertEq(registry.totalSupply(), 1, "Should have exactly 1 pet");
        
        // Pet should have data from latest position
        PetRegistry.Pet memory pet = registry.getPet(1);
        assertEq(pet.positionId, 300, "Pet should track latest position");
        
        vm.stopPrank();
    }

    // ============ Position Update Behavior Tests ============

    function testPetPositionDataIsCompletelyReplaced() public {
        vm.startPrank(hook);
        
        // User1 creates first position on pool1, position 100
        registry.hatchFromHook(user1, 11155111, poolId1, 100); // Sepolia
        
        // Verify initial state
        PetRegistry.Pet memory petBefore = registry.getPet(1);
        assertEq(petBefore.chainId, 11155111, "Initial chain: Sepolia");
        assertEq(petBefore.poolId, poolId1, "Initial pool");
        assertEq(petBefore.positionId, 100, "Initial position");
        
        // User1 creates second position on pool2, position 200, different chain
        registry.hatchFromHook(user1, 84532, poolId2, 200); // Base Sepolia
        
        // Verify pet data is COMPLETELY replaced
        PetRegistry.Pet memory petAfter = registry.getPet(1);
        assertEq(petAfter.chainId, 84532, "Chain should be updated to Base");
        assertEq(petAfter.poolId, poolId2, "Pool should be updated");
        assertEq(petAfter.positionId, 200, "Position should be updated");
        assertEq(petAfter.owner, user1, "Owner should remain same");
        assertEq(petAfter.health, 100, "Health should remain same (not reset)");
        
        vm.stopPrank();
    }

    function testPetMigrationEventEmittedOnSecondPosition() public {
        vm.startPrank(hook);
        
        // First position - emits PetHatchedFromLp
        vm.expectEmit(true, true, false, true);
        emit PetRegistry.PetHatchedFromLp(1, user1, block.chainid, poolId1, 100);
        registry.hatchFromHook(user1, block.chainid, poolId1, 100);
        
        // Second position - emits PetMigrated (not PetHatchedFromLp)
        vm.expectEmit(true, true, false, true);
        emit PetRegistry.PetMigrated(1, user1, block.chainid, block.chainid, poolId2, 200);
        registry.hatchFromHook(user1, block.chainid, poolId2, 200);
        
        vm.stopPrank();
    }

    function testActivePetIdMappingUpdatesCorrectly() public {
        vm.startPrank(hook);
        
        // User1 creates position
        uint256 petId = registry.hatchFromHook(user1, block.chainid, poolId1, 100);
        
        // Verify activePetId mapping
        assertEq(registry.activePetId(user1), petId, "Active pet should be set");
        assertEq(registry.activePetId(user2), 0, "User2 should have no active pet");
        
        // User1 creates second position
        uint256 samePetId = registry.hatchFromHook(user1, block.chainid, poolId1, 200);
        
        // Verify activePetId still points to same pet
        assertEq(registry.activePetId(user1), samePetId, "Active pet should still be same");
        assertEq(petId, samePetId, "Pet IDs should match");
        
        vm.stopPrank();
    }

    function testOwnerPetsArrayOnlyHasOnePet() public {
        vm.startPrank(hook);
        
        // User1 creates multiple positions
        registry.hatchFromHook(user1, block.chainid, poolId1, 100);
        registry.hatchFromHook(user1, block.chainid, poolId1, 200);
        registry.hatchFromHook(user1, block.chainid, poolId1, 300);
        
        // Get user's pets
        uint256[] memory userPets = registry.getPetsByOwner(user1);
        
        // Should only have 1 pet in array
        assertEq(userPets.length, 1, "User should have exactly 1 pet in array");
        assertEq(userPets[0], 1, "Pet ID should be 1");
        
        vm.stopPrank();
    }

    // ============ Cross-Chain Position Updates ============

    function testUserCanUpdatePetAcrossChains() public {
        vm.startPrank(hook);
        
        // User1 creates position on Sepolia
        uint256 petId = registry.hatchFromHook(user1, 11155111, poolId1, 100);
        
        PetRegistry.Pet memory petOnSepolia = registry.getPet(petId);
        assertEq(petOnSepolia.chainId, 11155111, "Should be on Sepolia");
        
        // User1 "travels" - creates position on Base
        uint256 samePetId = registry.hatchFromHook(user1, 84532, poolId2, 200);
        
        // Verify same pet, updated chain
        assertEq(petId, samePetId, "Should be same pet");
        PetRegistry.Pet memory petOnBase = registry.getPet(petId);
        assertEq(petOnBase.chainId, 84532, "Should be on Base now");
        assertEq(petOnBase.positionId, 200, "Should track new position");
        
        vm.stopPrank();
    }

    // ============ Edge Cases ============

    function testUserCanRecreateExactSamePosition() public {
        vm.startPrank(hook);
        
        // User1 creates position
        registry.hatchFromHook(user1, block.chainid, poolId1, 100);
        
        // User1 creates EXACT SAME position again
        uint256 petId = registry.hatchFromHook(user1, block.chainid, poolId1, 100);
        
        // Should still only have 1 pet
        assertEq(registry.totalSupply(), 1, "Should still have 1 pet");
        assertEq(petId, 1, "Should be same pet");
        
        vm.stopPrank();
    }

    function testLastUpdateTimestampChangesOnEachPosition() public {
        vm.startPrank(hook);
        
        // First position
        registry.hatchFromHook(user1, block.chainid, poolId1, 100);
        PetRegistry.Pet memory pet1 = registry.getPet(1);
        uint256 timestamp1 = pet1.lastUpdate;
        
        // Advance time
        vm.warp(block.timestamp + 1000);
        
        // Second position
        registry.hatchFromHook(user1, block.chainid, poolId1, 200);
        PetRegistry.Pet memory pet2 = registry.getPet(1);
        uint256 timestamp2 = pet2.lastUpdate;
        
        // Verify timestamp updated
        assertGt(timestamp2, timestamp1, "Timestamp should be updated");
        assertEq(timestamp2, block.timestamp, "Timestamp should be current");
        
        vm.stopPrank();
    }

    // ============ Implications for Health System ============

    /**
     * @notice Documents expected behavior for health monitoring
     * @dev When user creates a new position:
     *      1. Pet is updated to track new position
     *      2. Old position is NO LONGER tracked
     *      3. Health agent should recalculate health based on NEW position
     *      4. User cannot have multiple positions tracked by same pet
     */
    function testHealthImplicationsOfPositionUpdate() public {
        vm.startPrank(hook);
        
        // User1 creates position A (perfect range)
        registry.hatchFromHook(user1, block.chainid, poolId1, 100);
        
        // Simulate agent updating health to 95 (good position)
        vm.stopPrank();
        vm.startPrank(owner);
        registry.setAgent(owner);
        registry.updateHealth(1, 95, block.chainid);
        vm.stopPrank();
        
        // Verify health
        PetRegistry.Pet memory pet1 = registry.getPet(1);
        assertEq(pet1.health, 95, "Health should be 95");
        
        // User1 creates position B (new position, potentially different range)
        vm.startPrank(hook);
        registry.hatchFromHook(user1, block.chainid, poolId2, 200);
        vm.stopPrank();
        
        // IMPORTANT: Health does NOT reset to 100 automatically
        // Agent must recalculate health based on new position's range
        PetRegistry.Pet memory pet2 = registry.getPet(1);
        assertEq(pet2.health, 95, "Health persists (not reset)");
        assertEq(pet2.positionId, 200, "But position is updated");
        
        // Expected agent behavior after position update:
        // 1. Detect PetMigrated event
        // 2. Read new position data (positionId 200)
        // 3. Calculate health based on new position's tick range
        // 4. Call updateHealth() with new calculated health
    }

    function testMultiplePositionsSamPoolDifferentRanges() public {
        vm.startPrank(hook);
        
        // User1 creates tight range position
        registry.hatchFromHook(user1, block.chainid, poolId1, 100);
        PetRegistry.Pet memory pet1 = registry.getPet(1);
        assertEq(pet1.positionId, 100);
        
        // User1 creates wide range position (same pool, different range)
        registry.hatchFromHook(user1, block.chainid, poolId1, 200);
        PetRegistry.Pet memory pet2 = registry.getPet(1);
        assertEq(pet2.positionId, 200, "Should track new position");
        
        // Old position (100) is abandoned - pet only tracks position 200 now
        // If user wants both positions tracked, they need to use different wallets
        
        vm.stopPrank();
    }
}
