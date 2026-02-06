// ...existing code...
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PetRegistry is Ownable {
    struct Pet {
        address owner;
        uint256 health; // 0-100
        uint256 birthBlock;
        uint256 lastUpdate;
        uint256 chainId; // last station
        bytes32 poolId; // Uniswap v4 pool id
        uint256 positionId; // LP position id or NFT id (if applicable)
    }

    error NotHook(address caller);
    error InvalidOwner();
    error PetNotFound(uint256 petId);
    error InvalidHook(address hook);
    error InvalidAgent(address agent);
    error NotAgent(address caller);
    error NotOwner(address caller);
    error InvalidHealth(uint256 health);
    error PetAlreadyExists(address owner, uint256 existingPetId);

    address public hook;
    address public agent; // off-chain agent updater
    uint256 public nextId;
    mapping(uint256 => Pet) public pets;
    mapping(address => uint256[]) private ownerPets; // Track pets by owner
    mapping(address => uint256) public activePetId; // One active pet per user

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
    event HealthUpdated(uint256 indexed petId, uint256 health, uint256 chainId);
    event HookUpdated(address indexed hook);
    event AgentUpdated(address indexed agent);

    constructor(address initialOwner) Ownable(initialOwner) {
        // Owner set via Ownable constructor
    }

    function hatchFromHook(
        address owner,
        uint256 chainId,
        bytes32 poolId,
        uint256 positionId
    ) external returns (uint256 petId) {
        if (msg.sender != hook) revert NotHook(msg.sender);
        if (owner == address(0)) revert InvalidOwner();

        // Check if user already has an active pet
        uint256 existingPetId = activePetId[owner];
        
        if (existingPetId != 0) {
            // User already has a pet - this is a migration or new position
            // Update existing pet instead of creating duplicate
            Pet storage existingPet = pets[existingPetId];
            uint256 oldChainId = existingPet.chainId;
            
            existingPet.chainId = chainId;
            existingPet.poolId = poolId;
            existingPet.positionId = positionId;
            existingPet.lastUpdate = block.timestamp;
            
            emit PetMigrated(existingPetId, owner, oldChainId, chainId, poolId, positionId);
            return existingPetId;
        }

        // First pet for this user - mint new one
        petId = ++nextId;
        pets[petId] = Pet({
            owner: owner,
            health: 100,
            birthBlock: block.number,
            lastUpdate: block.timestamp,
            chainId: chainId,
            poolId: poolId,
            positionId: positionId
        });
        ownerPets[owner].push(petId);
        activePetId[owner] = petId; // Mark as active pet
        
        emit PetHatchedFromLp(petId, owner, chainId, poolId, positionId);
    }

    function updateHealth(uint256 petId, uint256 health, uint256 chainId) external {
        // TODO: Re-enable when agent system is implemented
        // if (msg.sender != agent) revert NotAgent(msg.sender);
        if (health > 100) revert InvalidHealth(health);

        Pet storage p = pets[petId];
        if (p.owner == address(0)) revert PetNotFound(petId);

        p.health = health;
        p.lastUpdate = block.timestamp;
        p.chainId = chainId;

        emit HealthUpdated(petId, health, chainId);
    }

    /// @notice Allows pet owner to manually update health (for demos without agent)
    /// @param petId The pet ID to update
    /// @param health New health value (0-100)
    function updateHealthManual(uint256 petId, uint256 health) external {
        Pet storage p = pets[petId];
        if (p.owner == address(0)) revert PetNotFound(petId);
        if (msg.sender != p.owner) revert NotOwner(msg.sender);
        if (health > 100) revert InvalidHealth(health);

        p.health = health;
        p.lastUpdate = block.timestamp;

        emit HealthUpdated(petId, health, p.chainId);
    }

    function setHook(address newHook) external onlyOwner {
        _setHook(newHook);
    }

    // ============ View Functions ============

    /// @notice Get user's active pet ID (the one linked to current LP)
    /// @param owner The owner address
    /// @return petId The active pet ID (0 if none)
    function getActivePetId(address owner) external view returns (uint256) {
        return activePetId[owner];
    }

    /// @notice Get full pet data
    /// @param petId The pet ID
    /// @return Pet struct with all data
    function getPet(uint256 petId) external view returns (Pet memory) {
        Pet memory p = pets[petId];
        if (p.owner == address(0)) revert PetNotFound(petId);
        return p;
    }

    /// @notice Get all pet IDs owned by an address
    /// @param owner The owner address
    /// @return Array of pet IDs
    function getPetsByOwner(address owner) external view returns (uint256[] memory) {
        return ownerPets[owner];
    }

    /// @notice Get total number of pets minted
    /// @return Total supply
    function totalSupply() external view returns (uint256) {
        return nextId;
    }

    /// @notice Check if a pet exists
    /// @param petId The pet ID
    /// @return true if pet exists
    function exists(uint256 petId) external view returns (bool) {
        return pets[petId].owner != address(0);
    }

    function setAgent(address newAgent) external onlyOwner {
        _setAgent(newAgent);
    }

    function _setHook(address newHook) internal {
        if (newHook == address(0)) revert InvalidHook(newHook);
        hook = newHook;
        emit HookUpdated(newHook);
    }

    function _setAgent(address newAgent) internal {
        if (newAgent == address(0)) revert InvalidAgent(newAgent);
        agent = newAgent;
        emit AgentUpdated(newAgent);
    }
}