// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PetRegistry} from "../../contracts/PetRegistry.sol";

contract PetRegistryTest is Test {
    PetRegistry public registry;
    
    address public owner = address(0x1);
    address public hook = address(0x2);
    address public agent = address(0x3);
    address public user1 = address(0x100);
    address public user2 = address(0x200);
    
    uint256 public constant CHAIN_ID = 11155111; // Sepolia
    bytes32 public constant POOL_ID = bytes32(uint256(1));
    uint256 public constant POSITION_ID = 1;

    event PetHatchedFromLp(
        uint256 indexed petId,
        address indexed owner,
        uint256 chainId,
        bytes32 poolId,
        uint256 positionId
    );

    event PetMigrated(
        uint256 indexed petId,
        address indexed owner,
        uint256 oldChainId,
        uint256 newChainId,
        bytes32 newPoolId,
        uint256 newPositionId
    );

    event HealthUpdated(
        uint256 indexed tokenId,
        uint256 newHealth,
        uint256 timestamp
    );

    function setUp() public {
        vm.startPrank(owner);
        registry = new PetRegistry(owner);
        registry.setHook(hook);
        registry.setAgent(agent);
        vm.stopPrank();
    }

    // ============ Hatching Tests ============

    function testHatchFromHook() public {
        vm.startPrank(hook);
        
        vm.expectEmit(true, true, false, true);
        emit PetHatchedFromLp(1, user1, CHAIN_ID, POOL_ID, POSITION_ID);
        
        uint256 tokenId = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, POSITION_ID);
        
        assertEq(tokenId, 1, "First token should be ID 1");
        
        PetRegistry.Pet memory pet = registry.getPet(tokenId);
        assertEq(pet.owner, user1, "Owner should be user1");
        
        vm.stopPrank();
    }

    function testHatchFromHookRevertsIfNotHook() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, POSITION_ID);
        
        vm.stopPrank();
    }

    function testMultipleHatches() public {
        vm.startPrank(hook);
        
        // First hatch - creates new pet
        uint256 tokenId1 = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 1);
        assertEq(tokenId1, 1, "First pet ID should be 1");
        
        // Second hatch for same user - UPDATES existing pet (migration behavior)
        vm.expectEmit(true, true, false, true);
        emit PetMigrated(1, user1, CHAIN_ID, CHAIN_ID, POOL_ID, 2);
        uint256 tokenId2 = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 2);
        assertEq(tokenId2, 1, "Should return same pet ID (no duplicate)");
        
        // Different user - creates NEW pet
        uint256 tokenId3 = registry.hatchFromHook(user2, CHAIN_ID, POOL_ID, 3);
        assertEq(tokenId3, 2, "Second user gets pet ID 2");
        
        // Total supply = 2 (one per user, not 3)
        assertEq(registry.totalSupply(), 2, "Total supply should be 2");
        
        vm.stopPrank();
    }

    // ============ Health Update Tests ============

    function testUpdateHealthByAgent() public {
        // First hatch a pet
        vm.prank(hook);
        uint256 tokenId = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, POSITION_ID);
        
        // Agent updates health
        vm.startPrank(agent);
        
        vm.expectEmit(true, false, false, false);
        emit HealthUpdated(tokenId, 75, CHAIN_ID);
        
        registry.updateHealth(tokenId, 75, CHAIN_ID);
        
        PetRegistry.Pet memory pet = registry.getPet(tokenId);
        assertEq(pet.health, 75, "Health should be 75");
        
        vm.stopPrank();
    }

    function testUpdateHealthManualByOwner() public {
        // First hatch a pet
        vm.prank(hook);
        uint256 tokenId = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, POSITION_ID);
        
        // Owner updates health manually
        vm.startPrank(user1);
        
        vm.expectEmit(true, false, false, false);
        emit HealthUpdated(tokenId, 50, block.timestamp);
        
        registry.updateHealthManual(tokenId, 50);
        
        PetRegistry.Pet memory pet = registry.getPet(tokenId);
        assertEq(pet.health, 50, "Health should be 50");
        
        vm.stopPrank();
    }

    function testUpdateHealthRevertsIfNotOwner() public {
        vm.prank(hook);
        uint256 tokenId = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, POSITION_ID);
        
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSelector(PetRegistry.NotOwner.selector, user2));
        registry.updateHealthManual(tokenId, 50);
        vm.stopPrank();
    }

    function testUpdateHealthRevertsIfInvalidHealthTooHigh() public {
        vm.prank(hook);
        uint256 tokenId = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, POSITION_ID);
        
        vm.startPrank(agent);
        vm.expectRevert(abi.encodeWithSelector(PetRegistry.InvalidHealth.selector, 101));
        registry.updateHealth(tokenId, 101, CHAIN_ID);
        vm.stopPrank();
    }

    function testUpdateHealthBoundaryValues() public {
        vm.prank(hook);
        uint256 tokenId = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, POSITION_ID);
        
        vm.startPrank(agent);
        
        // Test minimum valid health (0)
        registry.updateHealth(tokenId, 0, CHAIN_ID);
        PetRegistry.Pet memory pet1 = registry.getPet(tokenId);
        assertEq(pet1.health, 0, "Health should be 0");
        
        // Test maximum valid health (100)
        registry.updateHealth(tokenId, 100, CHAIN_ID);
        PetRegistry.Pet memory pet2 = registry.getPet(tokenId);
        assertEq(pet2.health, 100, "Health should be 100");
        
        vm.stopPrank();
    }

    // ============ View Function Tests ============

    function testGetPet() public {
        vm.prank(hook);
        uint256 tokenId = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, POSITION_ID);
        
        PetRegistry.Pet memory pet = registry.getPet(tokenId);
        
        assertEq(pet.owner, user1, "Owner should match");
        assertEq(pet.health, 100, "Initial health should be 100");
        assertEq(pet.lastUpdate, block.timestamp, "Last update should be current timestamp");
        assertEq(pet.chainId, CHAIN_ID, "Chain ID should match");
        assertEq(pet.poolId, POOL_ID, "Pool ID should match");
        assertEq(pet.positionId, POSITION_ID, "Position ID should match");
    }

    function testGetPetsByOwner() public {
        vm.startPrank(hook);
        
        // User1 hatches first pet
        uint256 tokenId1 = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 1);
        
        // User1 creates another LP position (migration) - updates same pet
        registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 2);
        
        // User2 gets their own pet
        uint256 tokenId3 = registry.hatchFromHook(user2, CHAIN_ID, POOL_ID, 3);
        
        vm.stopPrank();
        
        // Check user1's pets - should only have 1 (idempotent)
        uint256[] memory user1Pets = registry.getPetsByOwner(user1);
        assertEq(user1Pets.length, 1, "User1 should have 1 pet");
        assertEq(user1Pets[0], tokenId1, "Pet ID should match");
        
        // Check user2's pets
        uint256[] memory user2Pets = registry.getPetsByOwner(user2);
        assertEq(user2Pets.length, 1, "User2 should have 1 pet");
        assertEq(user2Pets[0], tokenId3);
        
        // Check non-owner
        uint256[] memory noPets = registry.getPetsByOwner(address(0x999));
        assertEq(noPets.length, 0, "Should have no pets");
    }

    function testTotalSupply() public {
        assertEq(registry.totalSupply(), 0, "Initial supply should be 0");
        
        vm.startPrank(hook);
        
        // User1 hatches first pet
        registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 1);
        assertEq(registry.totalSupply(), 1, "Supply should be 1");
        
        // User1 creates another position (migration) - NO new pet
        registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 2);
        assertEq(registry.totalSupply(), 1, "Supply should still be 1 (idempotent)");
        
        // User2 hatches their pet
        registry.hatchFromHook(user2, CHAIN_ID, POOL_ID, 3);
        assertEq(registry.totalSupply(), 2, "Supply should be 2");
        
        vm.stopPrank();
    }

    function testExists() public {
        assertFalse(registry.exists(1), "Token 1 should not exist");
        
        vm.prank(hook);
        uint256 tokenId = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, POSITION_ID);
        
        assertTrue(registry.exists(tokenId), "Token should exist after minting");
        assertFalse(registry.exists(999), "Non-existent token should return false");
    }

    // ============ Migration Tests ============

    function testPetMigration() public {
        vm.startPrank(hook);
        
        // Initial hatch on Sepolia
        uint256 petId = registry.hatchFromHook(user1, 11155111, POOL_ID, 100);
        
        PetRegistry.Pet memory petBefore = registry.getPet(petId);
        assertEq(petBefore.chainId, 11155111, "Should start on Sepolia");
        assertEq(petBefore.positionId, 100, "Initial position ID");
        
        // Migrate to Base Sepolia (new LP position)
        uint256 newChainId = 84532;
        bytes32 newPoolId = bytes32(uint256(2));
        uint256 newPositionId = 200;
        
        vm.expectEmit(true, true, false, true);
        emit PetMigrated(petId, user1, 11155111, newChainId, newPoolId, newPositionId);
        
        uint256 returnedId = registry.hatchFromHook(user1, newChainId, newPoolId, newPositionId);
        assertEq(returnedId, petId, "Should return same pet ID");
        
        PetRegistry.Pet memory petAfter = registry.getPet(petId);
        assertEq(petAfter.chainId, newChainId, "Should be on Base Sepolia");
        assertEq(petAfter.poolId, newPoolId, "Pool ID should update");
        assertEq(petAfter.positionId, newPositionId, "Position ID should update");
        assertEq(petAfter.owner, user1, "Owner unchanged");
        assertEq(petAfter.birthBlock, petBefore.birthBlock, "Birth block unchanged");
        
        vm.stopPrank();
    }

    function testActivePetTracking() public {
        vm.startPrank(hook);
        
        // User1 hatches pet
        uint256 pet1 = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 1);
        assertEq(registry.getActivePetId(user1), pet1, "Active pet should be set");
        
        // User2 hatches pet
        uint256 pet2 = registry.hatchFromHook(user2, CHAIN_ID, POOL_ID, 2);
        assertEq(registry.getActivePetId(user2), pet2, "User2 active pet should be set");
        assertEq(registry.getActivePetId(user1), pet1, "User1 active pet unchanged");
        
        // User without pet
        assertEq(registry.getActivePetId(address(0x999)), 0, "No active pet for new user");
        
        vm.stopPrank();
    }

    // ============ Access Control Tests ============

    function testOnlyHookCanHatch() public {
        vm.startPrank(user1);
        vm.expectRevert();
        registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, POSITION_ID);
        vm.stopPrank();
    }

    function testAccessControlManagement() public {
        address newHook = address(0x4);
        address newAgent = address(0x5);
        
        vm.startPrank(owner);
        
        // Update addresses
        registry.setHook(newHook);
        registry.setAgent(newAgent);
        
        assertEq(registry.hook(), newHook, "Hook should be updated");
        assertEq(registry.agent(), newAgent, "Agent should be updated");
        
        vm.stopPrank();
    }
}
