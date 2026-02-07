// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PetRegistry} from "../../contracts/PetRegistry.sol";

contract PetRegistryIntegrationTest is Test {
    PetRegistry public registry;
    
    address public owner = address(0x1);
    address public hook = address(0x2);
    address public agent = address(0x3);
    address public user1 = address(0x100);
    address public user2 = address(0x200);
    
    uint256 public constant CHAIN_ID = 11155111; // Sepolia
    bytes32 public constant POOL_ID = bytes32(uint256(1));

    /// @notice Helper to calculate deterministic pet ID (matches PetRegistry logic)
    function _derivePetId(address petOwner) internal pure returns (uint256) {
        return uint256(uint48(bytes6(keccak256(abi.encodePacked("XolotrainPet", petOwner)))));
    }

    function setUp() public {
        vm.startPrank(owner);
        registry = new PetRegistry(owner); // Owner is the contract owner
        registry.setHook(hook);
        registry.setAgent(agent);
        vm.stopPrank();
    }

    // ============ Integration Tests ============

    function testFullLifecycle() public {
        // 1. Hatch pet
        vm.prank(hook);
        uint256 tokenId = registry.hatchFromHook(user1, 0, CHAIN_ID, POOL_ID, 1);
        
        // 2. Check initial state
        PetRegistry.Pet memory pet1 = registry.getPet(tokenId);
        assertEq(pet1.owner, user1);
        assertEq(pet1.health, 100);
        
        // 3. Agent updates health
        vm.prank(agent);
        registry.updateHealth(tokenId, 80, CHAIN_ID);
        
        // 4. Check updated state
        PetRegistry.Pet memory pet2 = registry.getPet(tokenId);
        assertEq(pet2.health, 80);
        
        // 5. Owner manually updates health
        vm.prank(user1);
        registry.updateHealthManual(tokenId, 60);
        
        // 6. Check final state
        PetRegistry.Pet memory pet3 = registry.getPet(tokenId);
        assertEq(pet3.health, 60);
        
        // 7. Verify ownership tracking
        uint256[] memory pets = registry.getPetsByOwner(user1);
        assertEq(pets.length, 1);
        assertEq(pets[0], tokenId);
    }

    function testMultipleOwnersMultiplePets() public {
        // Calculate expected deterministic pet IDs
        uint256 user1PetId = _derivePetId(user1);
        uint256 user2PetId = _derivePetId(user2);
        
        vm.startPrank(hook);
        
        // User1 creates first position - mints pet
        registry.hatchFromHook(user1, 0, CHAIN_ID, POOL_ID, 1);
        
        // User1 creates second position - updates SAME pet (idempotent)
        registry.hatchFromHook(user1, 0, CHAIN_ID, POOL_ID, 2);
        
        // User2 creates positions - mints pet
        registry.hatchFromHook(user2, 0, CHAIN_ID, POOL_ID, 3);
        registry.hatchFromHook(user2, 0, CHAIN_ID, POOL_ID, 4);
        registry.hatchFromHook(user2, 0, CHAIN_ID, POOL_ID, 5);
        
        vm.stopPrank();
        
        // Verify total supply - 2 pets (one per user)
        assertEq(registry.totalSupply(), 2, "Should have 2 pets (one per user)");
        
        // Verify owner pet counts - each has ONE pet
        assertEq(registry.getPetsByOwner(user1).length, 1, "User1 should have 1 pet");
        assertEq(registry.getPetsByOwner(user2).length, 1, "User2 should have 1 pet");
        
        // Verify pets were updated to latest positions
        PetRegistry.Pet memory pet1 = registry.getPet(user1PetId);
        assertEq(pet1.positionId, 2, "User1 pet should be at position 2 (latest)");
        
        PetRegistry.Pet memory pet2 = registry.getPet(user2PetId);
        assertEq(pet2.positionId, 5, "User2 pet should be at position 5 (latest)");
        
        // Update health for both pets
        vm.startPrank(agent);
        registry.updateHealth(user1PetId, 90, CHAIN_ID);
        registry.updateHealth(user2PetId, 70, CHAIN_ID);
        vm.stopPrank();
        
        // Verify health values
        pet1 = registry.getPet(user1PetId);
        pet2 = registry.getPet(user2PetId);
        
        assertEq(pet1.health, 90);
        assertEq(pet2.health, 70);
    }
}
