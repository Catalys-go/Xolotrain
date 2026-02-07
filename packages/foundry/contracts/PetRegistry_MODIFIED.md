// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PetRegistry is Ownable {
    struct Pet {
        address owner;
        uint256 health;
        uint256 birthBlock;
        uint256 lastUpdate;
        uint256 chainId;
        bytes32 poolId;
        uint256 positionId;
    }

    error NotHook(address caller);
    error InvalidOwner();
    error PetNotFound(uint256 petId);
    error InvalidHook(address hook);
    error InvalidAgent(address agent);
    error NotAgent(address caller);
    error NotOwner(address caller);
    error InvalidHealth(uint256 health);
    error PetOwnerMismatch(uint256 petId, address expected, address actual); // ✅ NEW

    address public hook;
    address public agent;
    uint256 public nextId;
    mapping(uint256 => Pet) public pets;
    mapping(address => uint256[]) private ownerPets;
    mapping(address => uint256) public activePetId;

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

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice ✅ MODIFIED: Complete rewrite to handle petId parameter
    /// @param petId 0 for new pet, >0 for migration
    function hatchFromHook(
        address owner,
        uint256 petId,
        uint256 chainId,
        bytes32 poolId,
        uint256 positionId
    ) external returns (uint256) {
        if (msg.sender != hook) revert NotHook(msg.sender);
        if (owner == address(0)) revert InvalidOwner();

        // Case 1: petId == 0 → Initial hatch
        if (petId == 0) {
            uint256 existingPetId = activePetId[owner];
            
            if (existingPetId != 0) {
                // User already has a pet - update existing
                Pet storage existingPet = pets[existingPetId];
                uint256 oldChainId = existingPet.chainId;
                
                existingPet.chainId = chainId;
                existingPet.poolId = poolId;
                existingPet.positionId = positionId;
                existingPet.lastUpdate = block.timestamp;
                
                emit PetMigrated(existingPetId, owner, oldChainId, chainId, poolId, positionId);
                return existingPetId;
            }

            // First pet for this user - create new
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
            activePetId[owner] = petId;
            
            emit PetHatchedFromLp(petId, owner, chainId, poolId, positionId);
            return petId;
        }
        
        // Case 2: petId > 0 → Migration
        Pet storage existingPet = pets[petId];
        if (existingPet.owner == address(0)) revert PetNotFound(petId);
        if (existingPet.owner != owner) revert PetOwnerMismatch(petId, owner, existingPet.owner);
        
        uint256 oldChainId = existingPet.chainId;
        existingPet.chainId = chainId;
        existingPet.poolId = poolId;
        existingPet.positionId = positionId;
        existingPet.lastUpdate = block.timestamp;
        
        emit PetMigrated(petId, owner, oldChainId, chainId, poolId, positionId);
        return petId;
    }

    function updateHealth(uint256 petId, uint256 health, uint256 chainId) external {
        if (health > 100) revert InvalidHealth(health);

        Pet storage p = pets[petId];
        if (p.owner == address(0)) revert PetNotFound(petId);

        p.health = health;
        p.lastUpdate = block.timestamp;
        p.chainId = chainId;

        emit HealthUpdated(petId, health, chainId);
    }

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

    function getActivePetId(address owner) external view returns (uint256) {
        return activePetId[owner];
    }

    function getPet(uint256 petId) external view returns (Pet memory) {
        Pet memory p = pets[petId];
        if (p.owner == address(0)) revert PetNotFound(petId);
        return p;
    }

    function getPetsByOwner(address owner) external view returns (uint256[] memory) {
        return ownerPets[owner];
    }

    function totalSupply() external view returns (uint256) {
        return nextId;
    }

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
