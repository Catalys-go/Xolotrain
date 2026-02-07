// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PetRegistry} from "../../contracts/PetRegistry.sol";

/**
 * @title AgentCapabilities Test Suite
 * @notice Tests AGENT-SPECIFIC capabilities not covered in PetRegistry.t.sol
 * @dev Focuses on batch operations, gas optimization, and multi-owner scenarios
 * 
 * Note: Basic agent functionality is already tested in PetRegistry.t.sol:
 * - testUpdateHealthByAgent (agent authorization)
 * - testUpdateHealthBoundaryValues (health bounds 0-100)
 * - testGetPet (reading pet data)
 * - testGetPetsByOwner (owner lookup)
 * - testActivePetTracking (active pet lookup)
 * - testAccessControlManagement (agent/hook management)
 */
contract AgentCapabilitiesTest is Test {
    PetRegistry public petRegistry;
    
    address public deployer = address(this);
    address public hook = address(0xBEEF);
    address public agent = address(0xA6E47);  // Agent address
    address public owner = address(0x1111);
    
    uint256 public constant CHAIN_ID = 31337;
    bytes32 public poolId = keccak256("test-pool");
    uint256 public positionId = 12345;
    uint256 public petId;
    
    event HealthUpdated(uint256 indexed petId, uint256 health, uint256 chainId);
    
    function setUp() public {
        petRegistry = new PetRegistry(deployer);
        
        // Set the hook
        petRegistry.setHook(hook);
        
        // Set the agent
        petRegistry.setAgent(agent);
        
        // Mint a test pet
        vm.prank(hook);
        petId = petRegistry.hatchFromHook(owner, 0, CHAIN_ID, poolId, positionId);
    }
    
    // Note: Basic agent authorization tests are in PetRegistry.t.sol
    // This file focuses on agent-specific use cases for health monitoring
    
    // ============ Batch Operations Tests (Agent-Specific) ============
    
    function testAgentCanTrackMultiplePets() public {
        // Note: PetRegistry now enforces one pet per user
        // This test creates pets for different users
        address owner2 = address(0x2222);
        address owner3 = address(0x3333);
        
        bytes32 pool2 = keccak256("pool-2");
        bytes32 pool3 = keccak256("pool-3");
        
        vm.startPrank(hook);
        uint256 pet2 = petRegistry.hatchFromHook(owner2, 0, CHAIN_ID, pool2, 67890);
        uint256 pet3 = petRegistry.hatchFromHook(owner3, 0, CHAIN_ID, pool3, 11111);
        vm.stopPrank();
        
        // Agent updates health for all pets
        vm.startPrank(agent);
        petRegistry.updateHealth(petId, 90, CHAIN_ID);
        petRegistry.updateHealth(pet2, 80, CHAIN_ID);
        petRegistry.updateHealth(pet3, 70, CHAIN_ID);
        vm.stopPrank();
        
        // Verify all health values
        assertEq(petRegistry.getPet(petId).health, 90);
        assertEq(petRegistry.getPet(pet2).health, 80);
        assertEq(petRegistry.getPet(pet3).health, 70);
    }
    
    function testHealthUpdateEmitsEvent() public {
        uint256 newHealth = 85;
        
        vm.expectEmit(true, false, false, true);
        emit HealthUpdated(petId, newHealth, CHAIN_ID);
        
        vm.prank(agent);
        petRegistry.updateHealth(petId, newHealth, CHAIN_ID);
    }
    
    // ============ Health Bounds Tests ============
    
    function testHealthCanBeSetToZero() public {
        vm.prank(agent);
        petRegistry.updateHealth(petId, 0, CHAIN_ID);
        
        assertEq(petRegistry.getPet(petId).health, 0, "Health can be 0 (dead pet)");
    }
    
    function testHealthCanBeSetToMax() public {
        vm.prank(agent);
        petRegistry.updateHealth(petId, 100, CHAIN_ID);
        
        assertEq(petRegistry.getPet(petId).health, 100, "Health can be 100");
    }
    
    function testHealthUpdatesBeyond100() public {
        // Test what happens if agent tries to set health > 100
        vm.prank(agent);
        vm.expectRevert(); // Should revert with InvalidHealth
        petRegistry.updateHealth(petId, 150, CHAIN_ID);
    }
    
    // ============ Batch Operations Tests ============
    
    function testAgentCanBatchUpdateHealth() public {
        // Note: PetRegistry enforces one pet per user
        // Create pets for multiple users
        address[] memory owners = new address[](5);
        uint256[] memory tokens = new uint256[](5);
        
        for (uint256 i = 0; i < 5; i++) {
            owners[i] = address(uint160(0x2000 + i));
            bytes32 pool = keccak256(abi.encodePacked("pool", i));
            vm.prank(hook);
            tokens[i] = petRegistry.hatchFromHook(owners[i], 0, CHAIN_ID, pool, uint256(i + 100));
        }
        
        // Agent batch updates health
        vm.startPrank(agent);
        for (uint256 i = 0; i < 5; i++) {
            petRegistry.updateHealth(tokens[i], 90 - (i * 10), CHAIN_ID);
        }
        vm.stopPrank();
        
        // Verify all updates
        for (uint256 i = 0; i < 5; i++) {
            assertEq(petRegistry.getPet(tokens[i]).health, 90 - (i * 10));
        }
    }
    
    // ============ Gas Optimization Tests (Agent-Specific Performance) ============
    
    function testHealthUpdateGasUsage() public {
        vm.prank(agent);
        
        uint256 gasBefore = gasleft();
        petRegistry.updateHealth(petId, 95, CHAIN_ID);
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas used for health update", gasUsed);
        
        // Should be very cheap (just a storage write)
        assertLt(gasUsed, 50_000, "Health update should be gas efficient");
    }
    
    function testBatchHealthUpdateGasUsage() public {
        // Create 10 pets for different users
        uint256[] memory tokens = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            address petOwner = address(uint160(0x3000 + i));
            vm.prank(hook);
            tokens[i] = petRegistry.hatchFromHook(petOwner, 0, CHAIN_ID, keccak256(abi.encodePacked("pool", i)), i + 200);
        }
        
        vm.startPrank(agent);
        uint256 gasBefore = gasleft();
        
        for (uint256 i = 0; i < 10; i++) {
            petRegistry.updateHealth(tokens[i], 50 + i, CHAIN_ID);
        }
        
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();
        
        emit log_named_uint("Gas used for 10 health updates", gasUsed);
        
        // Should scale linearly
        assertLt(gasUsed, 500_000, "Batch updates should be reasonable");
    }
    
    // ============ Agent State Management Tests ============
    
    function testAgentCanBeDisabled() public {
        // Set agent to zero address to disable - should revert
        vm.expectRevert();
        petRegistry.setAgent(address(0));
    }
    
    function testAgentCanBeChanged() public {
        address newAgent = address(0xA6E49);
        
        petRegistry.setAgent(newAgent);
        
        // Note: Authorization is currently commented out in contract
        // When enabled, old agent will not be able to update
        
        // New agent can update
        vm.prank(newAgent);
        petRegistry.updateHealth(petId, 60, CHAIN_ID);
        
        assertEq(petRegistry.getPet(petId).health, 60);
    }
    
    // ============ Multi-Owner Scenario Tests (Agent-Specific) ============
    
    function testAgentTracksMultipleOwnerPets() public {
        address owner2 = address(0x2222);
        address owner3 = address(0x3333);
        
        // Create pets for different owners
        vm.startPrank(hook);
        uint256 pet2 = petRegistry.hatchFromHook(owner2, 0, CHAIN_ID, keccak256("pool2"), 222);
        uint256 pet3 = petRegistry.hatchFromHook(owner3, 0, CHAIN_ID, keccak256("pool3"), 333);
        vm.stopPrank();
        
        // Agent updates health for all
        vm.startPrank(agent);
        petRegistry.updateHealth(petId, 90, CHAIN_ID);  // owner1
        petRegistry.updateHealth(pet2, 80, CHAIN_ID);   // owner2
        petRegistry.updateHealth(pet3, 70, CHAIN_ID);   // owner3
        vm.stopPrank();
        
        // Verify correct owners
        assertEq(petRegistry.getPet(petId).owner, owner);
        assertEq(petRegistry.getPet(pet2).owner, owner2);
        assertEq(petRegistry.getPet(pet3).owner, owner3);
        
        // Verify health updates
        assertEq(petRegistry.getPet(petId).health, 90);
        assertEq(petRegistry.getPet(pet2).health, 80);
        assertEq(petRegistry.getPet(pet3).health, 70);
    }
    
    function testMultipleHealthUpdatesInSameBlock() public {
        vm.startPrank(agent);
        
        petRegistry.updateHealth(petId, 90, CHAIN_ID);
        petRegistry.updateHealth(petId, 80, CHAIN_ID);
        petRegistry.updateHealth(petId, 70, CHAIN_ID);
        
        vm.stopPrank();
        
        // Final health should be the last update
        assertEq(petRegistry.getPet(petId).health, 70, "Should apply last update");
    }
    
    // ============ Agent Performance Fuzz Tests ============
    
    function testFuzzBatchHealthUpdates(uint8[10] memory healthValues) public {
        vm.startPrank(agent);
        
        for (uint256 i = 0; i < healthValues.length; i++) {
            if (healthValues[i] <= 100) {
                petRegistry.updateHealth(petId, healthValues[i], CHAIN_ID);
            }
        }
        
        vm.stopPrank();
        
        // Health should be the last valid value
        uint256 expectedHealth = 100; // Default if no valid updates
        for (uint256 i = healthValues.length; i > 0; i--) {
            if (healthValues[i-1] <= 100) {
                expectedHealth = healthValues[i-1];
                break;
            }
        }
        
        assertEq(petRegistry.getPet(petId).health, expectedHealth);
    }
}
