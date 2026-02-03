// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolIdLibrary, PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract ShowPoolKeys is Script {
    using PoolIdLibrary for PoolKey;

    // Token addresses for different networks
    // For Ethereum Mainnet:
    address constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    
    // For Sepolia testnet:
    address constant WETH_SEPOLIA = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant USDT_SEPOLIA = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;

    // Fee tiers (in hundredths of a bip, so 3000 = 0.30%)
    uint24 constant FEE_ULTRA_LOW = 10; // 0.001%
    uint24 constant FEE_LOW = 100;      // 0.01%
    uint24 constant FEE_MEDIUM = 500;   // 0.05%
    uint24 constant FEE_HIGH = 3000;    // 0.30%
    uint24 constant FEE_VERY_HIGH = 10000; // 1.00%

    // Tick spacings
    int24 constant TICK_SPACING_LOW = 1;
    int24 constant TICK_SPACING_MEDIUM = 10;
    int24 constant TICK_SPACING_HIGH = 60;
    int24 constant TICK_SPACING_VERY_HIGH = 200;

    function run() external view {
        // Signature to run without hook address
        run(address(0));
    }

    function run(address hookAddress) public view {
        console.log("\n========================================");
        console.log("   UNISWAP V4 POOL KEY CALCULATOR");
        console.log("========================================\n");
        
        console.log("Network: MAINNET");
        console.log("Hook Address:", hookAddress);
        console.log("\n========================================\n");
        
        // ETH/USDC Pool
        printPoolKeyDetails(
            "ETH/USDC",
            WETH_MAINNET,
            USDC_MAINNET,
            FEE_MEDIUM,  // 0.05%
            TICK_SPACING_MEDIUM, // 10
            hookAddress 
        );
        
        // ETH/USDT Pool
        printPoolKeyDetails(
            "ETH/USDT",
            WETH_MAINNET,
            USDT_MAINNET,
            FEE_MEDIUM,  // 0.05%
            TICK_SPACING_MEDIUM, // 10
            hookAddress
        );
        
        // USDC/USDT Pool
        printPoolKeyDetails(
            "USDC/USDT",
            USDC_MAINNET,
            USDT_MAINNET,
            FEE_ULTRA_LOW,  // 0.001%
            TICK_SPACING_LOW, // 1
            hookAddress
        );
        
        console.log("========================================\n");
    }

    function printPoolKeyDetails(
        string memory name,
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickSpacing,
        address hookAddress
    ) internal view {
        // Ensure currency0 < currency1
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
        
        console.log("Pool:", name);
        console.log("---");
        console.log("currency0:", Currency.unwrap(key.currency0));
        console.log("currency1:", Currency.unwrap(key.currency1));
        console.log("fee:", key.fee, string.concat("(", getFeePercentString(key.fee), ")"));
        console.log("tickSpacing:", key.tickSpacing);
        console.log("hooks:", address(key.hooks));
        
        // Calculate and display pool ID
        bytes32 poolIdBytes = PoolId.unwrap(key.toId());
        console.log("Pool ID (bytes32):");
        console.logBytes32(poolIdBytes);
        console.log("");
    }

    function getFeePercentString(uint24 fee) internal pure returns (string memory) {
        if (fee == 10) return "0.001%";
        if (fee == 100) return "0.01%";
        if (fee == 500) return "0.05%";
        if (fee == 3000) return "0.30%";
        if (fee == 10000) return "1.00%";
        return "custom";
    }
}
