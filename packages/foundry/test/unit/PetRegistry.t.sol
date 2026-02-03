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

    event HealthUpdated(
        uint256 indexed tokenId,
        uint256 newHealth,
        uint256 timestamp
    );

    function setUp() public {
        vm.startPrank(owner);
        registry = new PetRegistry();
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
        
        uint256 tokenId1 = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 1);
        uint256 tokenId2 = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 2);
        uint256 tokenId3 = registry.hatchFromHook(user2, CHAIN_ID, POOL_ID, 3);
        
        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
        assertEq(tokenId3, 3);
        assertEq(registry.totalSupply(), 3);
        
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
        
        // User1 gets 2 pets
        uint256 tokenId1 = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 1);
        uint256 tokenId2 = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 2);
        
        // User2 gets 1 pet
        uint256 tokenId3 = registry.hatchFromHook(user2, CHAIN_ID, POOL_ID, 3);
        
        vm.stopPrank();
        
        // Check user1's pets
        uint256[] memory user1Pets = registry.getPetsByOwner(user1);
        assertEq(user1Pets.length, 2, "User1 should have 2 pets");
        assertEq(user1Pets[0], tokenId1);
        assertEq(user1Pets[1], tokenId2);
        
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
        registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 1);
        assertEq(registry.totalSupply(), 1, "Supply should be 1");
        
        registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 2);
        assertEq(registry.totalSupply(), 2, "Supply should be 2");
        
        registry.hatchFromHook(user2, CHAIN_ID, POOL_ID, 3);
        assertEq(registry.totalSupply(), 3, "Supply should be 3");
        
        vm.stopPrank();
    }

    function testExists() public {
        assertFalse(registry.exists(1), "Token 1 should not exist");
        
        vm.prank(hook);
        uint256 tokenId = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, POSITION_ID);
        
        assertTrue(registry.exists(tokenId), "Token should exist after minting");
        assertFalse(registry.exists(999), "Non-existent token should return false");
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
