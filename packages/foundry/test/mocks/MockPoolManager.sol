// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockPoolManager
 * @notice Simple mock for testing hooks that need to be called by PoolManager
 */
contract MockPoolManager {
    address public hookAddress;
    
    constructor(address _hook) {
        hookAddress = _hook;
    }
    
    function msgSender() external view returns (address) {
        return address(this);
    }
}
