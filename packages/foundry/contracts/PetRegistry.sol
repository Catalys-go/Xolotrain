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
    error PetOwnerMismatch(uint256 petId, address expected, address actual);

    address public hook;
    address public agent; // off-chain agent updater
    uint256 private _totalSupply; // Track total number of unique pets minted
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

    /// @notice Derive deterministic pet ID from owner address
    /// @dev Each user gets exactly one pet ID across all chains - prevents collisions
    /// @dev Uses uint48 (6 bytes) for UI-friendly IDs (~12-13 digits)
    /// @dev WARNING: Collision risk becomes significant above ~16.7 million users
    /// @dev If user base exceeds 10M, consider upgrading to uint64 or uint96
    /// @param owner The owner address
    /// @return petId Deterministic pet ID (same across all chains for this owner)
    function _derivePetId(address owner) internal pure returns (uint256) {
        return uint256(uint48(bytes6(keccak256(abi.encodePacked(
            "XolotrainPet",
            owner
        )))));
    }

    /// @notice Called by EggHatchHook when user adds liquidity
    /// @dev Handles both initial hatch and cross-chain migration
    /// @param owner Address of the LP position owner
    /// @param petId 0 for auto-derive (initial hatch), or explicit ID for migration
    /// @param chainId Current chain ID where LP was created
    /// @param poolId Uniswap v4 pool identifier
    /// @param positionId Unique LP position identifier
    /// @return petId The pet ID (derived or provided)
    function hatchFromHook(
        address owner,
        uint256 petId,
        uint256 chainId,
        bytes32 poolId,
        uint256 positionId
    ) external returns (uint256) {
        if (msg.sender != hook) revert NotHook(msg.sender);
        if (owner == address(0)) revert InvalidOwner();

        // Case 1: petId == 0 → Auto-derive from owner (initial hatch or local migration)
        if (petId == 0) {
            uint256 existingPetId = activePetId[owner];
            
            if (existingPetId != 0) {
                // User already has a pet on this chain - update it (local re-position)
                Pet storage repositionPet = pets[existingPetId];
                uint256 prevChainId = repositionPet.chainId;
                
                repositionPet.chainId = chainId;
                repositionPet.poolId = poolId;
                repositionPet.positionId = positionId;
                repositionPet.lastUpdate = block.timestamp;
                
                emit PetMigrated(existingPetId, owner, prevChainId, chainId, poolId, positionId);
                return existingPetId;
            }

            // First pet for this user - derive deterministic ID
            petId = _derivePetId(owner);
            
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
            activePetId[owner] = petId;
            _totalSupply++; // Increment total supply for new pet
            
            emit PetHatchedFromLp(petId, owner, chainId, poolId, positionId);
            return petId;
        }
        
        // Case 2: petId > 0 → Explicit cross-chain migration
        Pet storage existingPet = pets[petId];
        
        if (existingPet.owner == address(0)) {
            // Pet doesn't exist on this chain yet - create it
            pets[petId] = Pet({
                owner: owner,
                health: 100, // Start fresh or could be passed via hookData
                birthBlock: block.number,
                lastUpdate: block.timestamp,
                chainId: chainId,
                poolId: poolId,
                positionId: positionId
            });
            ownerPets[owner].push(petId);
            activePetId[owner] = petId;
            _totalSupply++; // Increment total supply for new pet on this chain
            
            emit PetMigrated(petId, owner, 0, chainId, poolId, positionId);
            return petId;
        }
        
        if (existingPet.owner != owner) {
            // Collision! Different owner already has this petId
            // This should never happen with owner-derived IDs
            revert PetOwnerMismatch(petId, owner, existingPet.owner);
        }
        
        // Same owner - update existing pet (re-migration to same chain)
        uint256 oldChainId = existingPet.chainId;
        existingPet.chainId = chainId;
        existingPet.poolId = poolId;
        existingPet.positionId = positionId;
        existingPet.lastUpdate = block.timestamp;
        activePetId[owner] = petId; // Update active pointer
        
        emit PetMigrated(petId, owner, oldChainId, chainId, poolId, positionId);
        return petId;
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
        return _totalSupply;
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