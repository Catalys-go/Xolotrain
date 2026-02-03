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

    function setUp() public {
        vm.startPrank(owner);
        registry = new PetRegistry();
        registry.setHook(hook);
        registry.setAgent(agent);
        vm.stopPrank();
    }

    // ============ Integration Tests ============

    function testFullLifecycle() public {
        // 1. Hatch pet
        vm.prank(hook);
        uint256 tokenId = registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 1);
        
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
        vm.startPrank(hook);
        
        // Create 5 pets for different owners
        registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 1);
        registry.hatchFromHook(user1, CHAIN_ID, POOL_ID, 2);
        registry.hatchFromHook(user2, CHAIN_ID, POOL_ID, 3);
        registry.hatchFromHook(user2, CHAIN_ID, POOL_ID, 4);
        registry.hatchFromHook(user2, CHAIN_ID, POOL_ID, 5);
        
        vm.stopPrank();
        
        // Verify total supply
        assertEq(registry.totalSupply(), 5);
        
        // Verify owner pet counts
        assertEq(registry.getPetsByOwner(user1).length, 2);
        assertEq(registry.getPetsByOwner(user2).length, 3);
        
        // Update health for various pets
        vm.startPrank(agent);
        registry.updateHealth(1, 90, CHAIN_ID);
        registry.updateHealth(3, 70, CHAIN_ID);
        registry.updateHealth(5, 50, CHAIN_ID);
        vm.stopPrank();
        
        // Verify health values
        PetRegistry.Pet memory pet1 = registry.getPet(1);
        PetRegistry.Pet memory pet3 = registry.getPet(3);
        PetRegistry.Pet memory pet5 = registry.getPet(5);
        
        assertEq(pet1.health, 90);
        assertEq(pet3.health, 70);
        assertEq(pet5.health, 50);
    }
}
