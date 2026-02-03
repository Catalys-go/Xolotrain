// ...existing code...
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PetRegistry is Ownable {
    struct Pet {
        address owner;
        uint256 health; // 0-100
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

    address public hook;
    address public agent; // off-chain agent updater
    uint256 public nextId;
    mapping(uint256 => Pet) public pets;

    event PetHatchedFromLp(
        uint256 indexed petId,
        address indexed owner,
        uint256 chainId,
        bytes32 poolId,
        uint256 positionId
    );
    event HealthUpdated(uint256 indexed petId, uint256 health, uint256 chainId);
    event HookUpdated(address indexed hook);
    event AgentUpdated(address indexed agent);

    constructor(/* address _hook, address _agent */) Ownable(msg.sender) {
        //_setHook(_hook);        
        //_setAgent(_agent);
    }

    function hatchFromHook(
        address owner,
        uint256 chainId,
        bytes32 poolId,
        uint256 positionId
    ) external returns (uint256 petId) {
        if (msg.sender != hook) revert NotHook(msg.sender);
        if (owner == address(0)) revert InvalidOwner();

        petId = ++nextId;
        pets[petId] = Pet({
            owner: owner,
            health: 100,
            lastUpdate: block.timestamp,
            chainId: chainId,
            poolId: poolId,
            positionId: positionId
        });
        emit PetHatchedFromLp(petId, owner, chainId, poolId, positionId);
    }

    function updateHealth(uint256 petId, uint256 health, uint256 chainId) external {
        if (msg.sender != agent) revert NotAgent(msg.sender);

        Pet storage p = pets[petId];
        if (p.owner == address(0)) revert PetNotFound(petId);

        p.health = health;
        p.lastUpdate = block.timestamp;
        p.chainId = chainId;

        emit HealthUpdated(petId, health, chainId);
    }

    function setHook(address newHook) external onlyOwner {
        _setHook(newHook);
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