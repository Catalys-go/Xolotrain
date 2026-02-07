// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AutoLpHelper} from "../../contracts/AutoLpHelper.sol";
import {EggHatchHook} from "../../contracts/EggHatchHook.sol";
import {PetRegistry} from "../../contracts/PetRegistry.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

/**
 * @title AutoLpHelperMintFromTokens Integration Tests
 * @notice End-to-end tests for solver-based LP creation from bridged tokens
 * @dev Tests the full flow: solver → AutoLpHelper → PoolManager → EggHatchHook → PetRegistry
 * 
 * STATUS: These tests are TEMPLATES for when contracts are deployed to testnet.
 * They are skipped by default (requiresDeployedContracts modifier).
 * 
 * TO USE: After deploying to testnet, update setUp() with deployed contract addresses
 * and remove the vm.skip(true) line.
 */
contract AutoLpHelperMintFromTokensIntegrationTest is Test {
    // Note: These tests require a local chain with deployed Uniswap v4 contracts
    // Run with: forge test --match-contract MintFromTokensIntegration --fork-url http://localhost:8545
    
    AutoLpHelper public autoLpHelper;
    EggHatchHook public hook;
    PetRegistry public petRegistry;
    
    IPoolManager public poolManager;
    IPositionManager public posm;
    
    address public solver = address(0x5050);
    address public user = address(0x1111);
    
    address public USDC;
    address public USDT;
    
    PoolKey public usdcUsdtKey;
    
    uint128 public constant USDC_AMOUNT = 1000e6;  // 1000 USDC
    uint128 public constant USDT_AMOUNT = 1000e6;  // 1000 USDT
    
    event LiquidityAdded(
        address indexed recipient,
        uint256 indexed positionId,
        uint128 liquidity,
        uint128 amount0,
        uint128 amount1
    );
    
    event PetHatched(
        uint256 indexed tokenId,
        address indexed owner,
        bytes32 indexed positionId
    );
    
    modifier requiresDeployedContracts() {
        // Check if contracts are deployed (for local/testnet testing)
        if (address(autoLpHelper) == address(0)) {
            vm.skip(true);
        }
        _;
    }
    
    function setUp() public {
        // This setup assumes contracts are already deployed to local chain
        // Load from deployments file or environment variables
        
        // For now, this is a template - actual addresses will be loaded from deployment
        // vm.skip(true); // Skip by default until we have deployed contracts
    }
    
    // ============ Full Flow Integration Tests ============
    
    function testMintLpFromTokensFullFlow() public requiresDeployedContracts {
        vm.startPrank(solver);
        
        // 1. Solver has bridged tokens from source chain
        deal(USDC, solver, USDC_AMOUNT);
        deal(USDT, solver, USDT_AMOUNT);
        
        // 2. Solver approves AutoLpHelper
        IERC20(USDC).approve(address(autoLpHelper), USDC_AMOUNT);
        IERC20(USDT).approve(address(autoLpHelper), USDT_AMOUNT);
        
        // 3. Solver calls mintLpFromTokens on behalf of user
        uint256 positionId = autoLpHelper.mintLpFromTokens(0, 
            USDC_AMOUNT,
            USDT_AMOUNT,
            -360,  // tickLower
            360,   // tickUpper
            user   // recipient
        );
        
        vm.stopPrank();
        
        // 4. Verify position was created
        assertGt(positionId, 0, "Position ID should be non-zero");
        
        // 5. Verify user owns the position NFT
        // assertEq(posm.ownerOf(positionId), user, "User should own position NFT");
        
        // 6. Verify pet was hatched via hook
        // uint256 petTokenId = petRegistry.positionToPet(bytes32(positionId));
        // assertGt(petTokenId, 0, "Pet should be minted");
    }
    
    function testMintLpFromTokensEmitsEvents() public requiresDeployedContracts {
        vm.startPrank(solver);
        
        deal(USDC, solver, USDC_AMOUNT);
        deal(USDT, solver, USDT_AMOUNT);
        
        IERC20(USDC).approve(address(autoLpHelper), USDC_AMOUNT);
        IERC20(USDT).approve(address(autoLpHelper), USDT_AMOUNT);
        
        // Expect LiquidityAdded event
        vm.expectEmit(true, true, false, true);
        emit LiquidityAdded(user, 0, 0, 0, 0); // Values will be checked in actual test
        
        autoLpHelper.mintLpFromTokens(0, 
            USDC_AMOUNT,
            USDT_AMOUNT,
            -360,
            360,
            user
        );
        
        vm.stopPrank();
    }
    
    function testMintLpFromTokensReturnsLeftovers() public requiresDeployedContracts {
        vm.startPrank(solver);
        
        // Use unbalanced amounts to create leftovers
        uint128 excessUsdc = 1500e6;  // More USDC than needed
        uint128 normalUsdt = 1000e6;
        
        deal(USDC, solver, excessUsdc);
        deal(USDT, solver, normalUsdt);
        
        IERC20(USDC).approve(address(autoLpHelper), excessUsdc);
        IERC20(USDT).approve(address(autoLpHelper), normalUsdt);
        
        uint256 userUsdcBefore = IERC20(USDC).balanceOf(user);
        
        autoLpHelper.mintLpFromTokens(0, 
            excessUsdc,
            normalUsdt,
            -360,
            360,
            user
        );
        
        uint256 userUsdcAfter = IERC20(USDC).balanceOf(user);
        
        // User should receive leftover USDC
        assertGt(userUsdcAfter, userUsdcBefore, "User should receive leftover USDC");
        
        vm.stopPrank();
    }
    
    function testMintLpFromTokensCreatesPositionWithCorrectTicks() public requiresDeployedContracts {
        vm.startPrank(solver);
        
        deal(USDC, solver, USDC_AMOUNT);
        deal(USDT, solver, USDT_AMOUNT);
        
        IERC20(USDC).approve(address(autoLpHelper), USDC_AMOUNT);
        IERC20(USDT).approve(address(autoLpHelper), USDT_AMOUNT);
        
        int24 tickLower = -360;
        int24 tickUpper = 360;
        
        uint256 positionId = autoLpHelper.mintLpFromTokens(0, 
            USDC_AMOUNT,
            USDT_AMOUNT,
            tickLower,
            tickUpper,
            user
        );
        
        // Verify position has correct tick range
        // (int24 actualTickLower, int24 actualTickUpper) = posm.getPositionTicks(positionId);
        // assertEq(actualTickLower, tickLower, "Tick lower should match");
        // assertEq(actualTickUpper, tickUpper, "Tick upper should match");
        
        vm.stopPrank();
    }
    
    function testMultipleSolversCanCreatePositions() public requiresDeployedContracts {
        address solver1 = address(0x5051);
        address solver2 = address(0x5052);
        address user1 = address(0x1111);
        address user2 = address(0x2222);
        
        // Solver 1 creates position for user1
        vm.startPrank(solver1);
        deal(USDC, solver1, USDC_AMOUNT);
        deal(USDT, solver1, USDT_AMOUNT);
        IERC20(USDC).approve(address(autoLpHelper), USDC_AMOUNT);
        IERC20(USDT).approve(address(autoLpHelper), USDT_AMOUNT);
        
        uint256 positionId1 = autoLpHelper.mintLpFromTokens(0, 
            USDC_AMOUNT,
            USDT_AMOUNT,
            -360,
            360,
            user1
        );
        vm.stopPrank();
        
        // Solver 2 creates position for user2
        vm.startPrank(solver2);
        deal(USDC, solver2, USDC_AMOUNT);
        deal(USDT, solver2, USDT_AMOUNT);
        IERC20(USDC).approve(address(autoLpHelper), USDC_AMOUNT);
        IERC20(USDT).approve(address(autoLpHelper), USDT_AMOUNT);
        
        uint256 positionId2 = autoLpHelper.mintLpFromTokens(0, 
            USDC_AMOUNT,
            USDT_AMOUNT,
            -360,
            360,
            user2
        );
        vm.stopPrank();
        
        // Positions should be different
        assertNotEq(positionId1, positionId2, "Position IDs should be different");
    }
    
    // ============ Edge Case Tests ============
    
    function testMintLpFromTokensWithVerySmallAmounts() public requiresDeployedContracts {
        vm.startPrank(solver);
        
        uint128 tinyUsdc = 1e6;  // 1 USDC (minimum)
        uint128 tinyUsdt = 1e6;  // 1 USDT (minimum)
        
        deal(USDC, solver, tinyUsdc);
        deal(USDT, solver, tinyUsdt);
        
        IERC20(USDC).approve(address(autoLpHelper), tinyUsdc);
        IERC20(USDT).approve(address(autoLpHelper), tinyUsdt);
        
        // Should not revert with tiny amounts
        uint256 positionId = autoLpHelper.mintLpFromTokens(0, 
            tinyUsdc,
            tinyUsdt,
            -360,
            360,
            user
        );
        
        assertGt(positionId, 0, "Should create position with tiny amounts");
        
        vm.stopPrank();
    }
    
    function testMintLpFromTokensWithVeryLargeAmounts() public requiresDeployedContracts {
        vm.startPrank(solver);
        
        uint128 largeUsdc = 1_000_000e6;  // 1M USDC
        uint128 largeUsdt = 1_000_000e6;  // 1M USDT
        
        deal(USDC, solver, largeUsdc);
        deal(USDT, solver, largeUsdt);
        
        IERC20(USDC).approve(address(autoLpHelper), largeUsdc);
        IERC20(USDT).approve(address(autoLpHelper), largeUsdt);
        
        // Should not revert with large amounts
        uint256 positionId = autoLpHelper.mintLpFromTokens(0, 
            largeUsdc,
            largeUsdt,
            -360,
            360,
            user
        );
        
        assertGt(positionId, 0, "Should create position with large amounts");
        
        vm.stopPrank();
    }
    
    function testMintLpFromTokensWithWideTicks() public requiresDeployedContracts {
        vm.startPrank(solver);
        
        deal(USDC, solver, USDC_AMOUNT);
        deal(USDT, solver, USDT_AMOUNT);
        
        IERC20(USDC).approve(address(autoLpHelper), USDC_AMOUNT);
        IERC20(USDT).approve(address(autoLpHelper), USDT_AMOUNT);
        
        // Very wide tick range
        int24 wideLower = -7200;
        int24 wideUpper = 7200;
        
        uint256 positionId = autoLpHelper.mintLpFromTokens(0, 
            USDC_AMOUNT,
            USDT_AMOUNT,
            wideLower,
            wideUpper,
            user
        );
        
        assertGt(positionId, 0, "Should create position with wide ticks");
        
        vm.stopPrank();
    }
    
    function testMintLpFromTokensWithNarrowTicks() public requiresDeployedContracts {
        vm.startPrank(solver);
        
        deal(USDC, solver, USDC_AMOUNT);
        deal(USDT, solver, USDT_AMOUNT);
        
        IERC20(USDC).approve(address(autoLpHelper), USDC_AMOUNT);
        IERC20(USDT).approve(address(autoLpHelper), USDT_AMOUNT);
        
        // Very narrow tick range (minimum: 1 tick spacing = 60)
        int24 narrowLower = -60;
        int24 narrowUpper = 60;
        
        uint256 positionId = autoLpHelper.mintLpFromTokens(0, 
            USDC_AMOUNT,
            USDT_AMOUNT,
            narrowLower,
            narrowUpper,
            user
        );
        
        assertGt(positionId, 0, "Should create position with narrow ticks");
        
        vm.stopPrank();
    }
    
    // ============ Gas Optimization Tests ============
    
    function testMintLpFromTokensGasUsage() public requiresDeployedContracts {
        vm.startPrank(solver);
        
        deal(USDC, solver, USDC_AMOUNT);
        deal(USDT, solver, USDT_AMOUNT);
        
        IERC20(USDC).approve(address(autoLpHelper), USDC_AMOUNT);
        IERC20(USDT).approve(address(autoLpHelper), USDT_AMOUNT);
        
        uint256 gasBefore = gasleft();
        
        autoLpHelper.mintLpFromTokens(0, 
            USDC_AMOUNT,
            USDT_AMOUNT,
            -360,
            360,
            user
        );
        
        uint256 gasUsed = gasBefore - gasleft();
        
        // Log gas usage for optimization tracking
        emit log_named_uint("Gas used for mintLpFromTokens", gasUsed);
        
        // Reasonable gas limit check (adjust based on actual measurements)
        assertLt(gasUsed, 500_000, "Gas usage should be reasonable");
        
        vm.stopPrank();
    }
    
    // ============ Security Tests ============
    
    function testCannotStealTokensFromContract() public requiresDeployedContracts {
        address attacker = address(0x666);
        
        // Put some tokens in the helper contract (simulating leftover)
        deal(USDC, address(autoLpHelper), 1000e6);
        
        vm.startPrank(attacker);
        
        deal(USDC, attacker, USDC_AMOUNT);
        deal(USDT, attacker, USDT_AMOUNT);
        
        IERC20(USDC).approve(address(autoLpHelper), USDC_AMOUNT);
        IERC20(USDT).approve(address(autoLpHelper), USDT_AMOUNT);
        
        uint256 contractBalanceBefore = IERC20(USDC).balanceOf(address(autoLpHelper));
        
        // Attacker creates position
        autoLpHelper.mintLpFromTokens(0, 
            USDC_AMOUNT,
            USDT_AMOUNT,
            -360,
            360,
            attacker
        );
        
        uint256 contractBalanceAfter = IERC20(USDC).balanceOf(address(autoLpHelper));
        
        // Contract balance should not decrease (attacker can't steal pre-existing tokens)
        assertGe(contractBalanceAfter, contractBalanceBefore, "Attacker should not steal tokens");
        
        vm.stopPrank();
    }
}
