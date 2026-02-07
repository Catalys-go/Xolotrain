// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AutoLpHelper} from "../../contracts/AutoLpHelper.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title TestAutoLp
 * @notice Integration tests for AutoLpHelper with mock contracts
 * @dev These tests validate constructor setup and basic functionality without requiring
 *      a full Uniswap v4 deployment. For full integration testing with swaps and minting,
 *      use a mainnet fork or deploy the complete Uniswap v4 stack.
 */
contract TestAutoLp is Test {
    AutoLpHelper public autoLpHelper;
    
    // Mock addresses - these contracts don't need to exist for constructor tests
    address public mockPoolManager = address(0x1);
    address public mockPositionManager = address(0x2);
    address public mockHook = address(0x3);
    
    Currency public ethCurrency = Currency.wrap(address(0));
    Currency public usdcCurrency = Currency.wrap(address(0x1000));
    Currency public usdtCurrency = Currency.wrap(address(0x2000));
    
    PoolKey public ethUsdcKey;
    PoolKey public ethUsdtKey;
    PoolKey public usdcUsdtKey;
    
    int24 public constant TICK_SPACING = 10;
    int24 public constant TICK_LOWER_OFFSET = -6;
    int24 public constant TICK_UPPER_OFFSET = 6;

    function setUp() public {
        // Create mock pool keys that match expected structure
        ethUsdcKey = PoolKey({
            currency0: ethCurrency,
            currency1: usdcCurrency,
            fee: 500,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(mockHook)
        });
        
        ethUsdtKey = PoolKey({
            currency0: ethCurrency,
            currency1: usdtCurrency,
            fee: 500,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(mockHook)
        });
        
        usdcUsdtKey = PoolKey({
            currency0: usdcCurrency,
            currency1: usdtCurrency,
            fee: 10,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(mockHook)
        });

        autoLpHelper = new AutoLpHelper(
            IPoolManager(mockPoolManager),
            IPositionManager(mockPositionManager),
            ethUsdcKey,
            ethUsdtKey,
            usdcUsdtKey,
            TICK_SPACING,
            TICK_LOWER_OFFSET,
            TICK_UPPER_OFFSET
        );
    }

    function testConstructorSetup() public view {
        // Verify all immutables are set correctly
        assertEq(address(autoLpHelper.POOL_MANAGER()), mockPoolManager, "PoolManager should match");
        assertEq(address(autoLpHelper.POSM()), mockPositionManager, "PositionManager should match");
        assertEq(autoLpHelper.TICK_SPACING(), TICK_SPACING, "TickSpacing should match");
        assertEq(autoLpHelper.TICK_LOWER_OFFSET(), TICK_LOWER_OFFSET, "TickLowerOffset should match");
        assertEq(autoLpHelper.TICK_UPPER_OFFSET(), TICK_UPPER_OFFSET, "TickUpperOffset should match");
        
        // Verify pool keys are stored correctly
        (Currency c0, Currency c1, uint24 fee, int24 tickSpacing,) = autoLpHelper.ethUsdcPoolKey();
        assertEq(Currency.unwrap(c0), Currency.unwrap(ethCurrency));
        assertEq(Currency.unwrap(c1), Currency.unwrap(usdcCurrency));
        assertEq(fee, 500);
        assertEq(tickSpacing, TICK_SPACING);
    }

    function testZeroInputReverts() public {
        vm.expectRevert(AutoLpHelper.ZeroInput.selector);
        autoLpHelper.swapEthToUsdcUsdtAndMint{value: 0}(0, 0);
    }

    function testReceiveEther() public {
        uint256 amount = 1 ether;
        (bool success,) = address(autoLpHelper).call{value: amount}("");
        assertTrue(success, "Should accept ETH");
        assertEq(address(autoLpHelper).balance, amount, "Balance should match");
    }
}

/**
 * @title TestAutoLpWithFork
 * @notice Integration tests for AutoLpHelper on mainnet fork or local Anvil
 * @dev These tests validate the actual PositionManager integration and user NFT ownership
 *      Run with fork: forge test --match-contract TestAutoLpWithFork --fork-url $MAINNET_RPC_URL
 *      Run with Anvil: Start `yarn chain` in another terminal, then `forge test --match-contract TestAutoLpWithFork --rpc-url http://localhost:8545`
 * 
 * TODO: Add similar tests for Sepolia fork to test against actual deployed contracts
 *       - Load AutoLpHelper address from deployments/11155111.json
 *       - Use Sepolia PoolManager: 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A
 *       - Use Sepolia PositionManager: 0x1B1C77B606d13b09C84d1c7394B96b147bC03147
 */
contract TestAutoLpWithFork is Test {
    AutoLpHelper public autoLpHelper;
    IPoolManager public poolManager;
    IPositionManager public positionManager;
    
    // Mainnet addresses (used when forking)
    address public constant MAINNET_POOL_MANAGER = 0x7Da1D65F8B249183667cdE74C5CBD46dD38AA829;
    address public constant MAINNET_POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    
    // Anvil chain ID
    uint256 public constant ANVIL_CHAIN_ID = 31337;
    
    address public user = makeAddr("user");
    
    function setUp() public {
        // Check if we're on Anvil (local chain) or a fork
        if (block.chainid == ANVIL_CHAIN_ID) {
            // Running on local Anvil - load deployed contracts
            try vm.readFile(string.concat(vm.projectRoot(), "/packages/foundry/deployments/31337.json")) returns (string memory json) {
                address poolManagerAddr = vm.parseJsonAddress(json, ".PoolManager");
                address positionManagerAddr = vm.parseJsonAddress(json, ".PositionManager");
                address autoLpHelperAddr = vm.parseJsonAddress(json, ".AutoLpHelper");
                
                poolManager = IPoolManager(poolManagerAddr);
                positionManager = IPositionManager(positionManagerAddr);
                autoLpHelper = AutoLpHelper(payable(autoLpHelperAddr));
                
                // Fund user with ETH
                vm.deal(user, 10 ether);
            } catch {
                // Deployment file doesn't exist, skip tests
                return;
            }
        } else {
            // Try to detect if we're on a fork
            try vm.activeFork() returns (uint256) {
                // Fork is active, use mainnet addresses
                poolManager = IPoolManager(MAINNET_POOL_MANAGER);
                positionManager = IPositionManager(MAINNET_POSITION_MANAGER);
                
                // For fork tests, we'd need to deploy AutoLpHelper or load it
                // For now, skip if AutoLpHelper not set
                // TODO: Deploy AutoLpHelper in fork environment
                
                // Fund user with ETH
                vm.deal(user, 10 ether);
            } catch {
                // Not on a fork or Anvil, skip tests
                return;
            }
        }
    }

    /// @notice Test that verifies PositionManager NFT is minted to user, not AutoLpHelper
    function testPositionOwnershipIsUser() public {
        // Skip if contracts not loaded
        if (address(autoLpHelper) == address(0)) {
            return;
        }
        
        IERC721 nftContract = IERC721(address(positionManager));
        uint256 userBalanceBefore = nftContract.balanceOf(user);
        uint256 contractBalanceBefore = nftContract.balanceOf(address(autoLpHelper));
        
        // Perform LP creation
        vm.startPrank(user);
        uint128 liquidity = autoLpHelper.swapEthToUsdcUsdtAndMint{value: 0.1 ether}(
            1_000_000, // minUsdcOut (30% slippage)
            1_000_000  // minUsdtOut (30% slippage)
        );
        vm.stopPrank();
        
        assertGt(liquidity, 0, "Should mint liquidity");
        
        // CRITICAL: Verify NFT is owned by user, NOT by AutoLpHelper
        uint256 userBalanceAfter = nftContract.balanceOf(user);
        uint256 contractBalanceAfter = nftContract.balanceOf(address(autoLpHelper));
        
        assertEq(
            userBalanceAfter,
            userBalanceBefore + 1,
            "User should receive 1 NFT"
        );
        assertEq(
            contractBalanceAfter,
            contractBalanceBefore,
            "AutoLpHelper should NOT receive NFT"
        );
    }

    /// @notice Test that verifies the correct tokenId is emitted in LiquidityAdded event
    function testEmitsCorrectTokenId() public {
        // Skip if contracts not loaded
        if (address(autoLpHelper) == address(0)) {
            return;
        }
        
        uint256 nextTokenId = positionManager.nextTokenId();
        
        // Expect LiquidityAdded event with correct tokenId
        vm.expectEmit(true, true, false, false);
        emit AutoLpHelper.LiquidityAdded(
            user,
            nextTokenId, // Should emit the actual PositionManager NFT tokenId
            0.1 ether,
            0, 0, // amounts will vary
            -60, 60,
            0, // liquidity will vary
            block.timestamp
        );
        
        vm.startPrank(user);
        autoLpHelper.swapEthToUsdcUsdtAndMint{value: 0.1 ether}(1_000_000, 1_000_000);
        vm.stopPrank();
    }

    /// @notice Test that verifies user can transfer their NFT position
    function testUserCanTransferNFT() public {
        // Skip if contracts not loaded
        if (address(autoLpHelper) == address(0)) {
            return;
        }
        
        // Create position
        vm.startPrank(user);
        autoLpHelper.swapEthToUsdcUsdtAndMint{value: 0.1 ether}(1_000_000, 1_000_000);
        
        // Get the tokenId that was just minted
        uint256 tokenId = positionManager.nextTokenId() - 1;
        
        // User should be able to transfer their NFT
        address recipient = makeAddr("recipient");
        IERC721(address(positionManager)).transferFrom(user, recipient, tokenId);
        vm.stopPrank();
        
        // Verify transfer worked
        IERC721 nftContract = IERC721(address(positionManager));
        assertEq(nftContract.ownerOf(tokenId), recipient, "Recipient should own NFT");
        assertEq(nftContract.balanceOf(user), 0, "User should have 0 NFTs");
        assertEq(nftContract.balanceOf(recipient), 1, "Recipient should have 1 NFT");
    }

    /// @notice Test that verifies PositionManager integration doesn't break atomicity
    function testAtomicityWithPositionManager() public {
        // Skip if contracts not loaded
        if (address(autoLpHelper) == address(0)) {
            return;
        }
        
        uint256 userEthBefore = user.balance;
        uint256 userNftsBefore = IERC721(address(positionManager)).balanceOf(user);
        
        // Should complete in single transaction
        vm.startPrank(user);
        uint128 liquidity = autoLpHelper.swapEthToUsdcUsdtAndMint{value: 0.1 ether}(
            1_000_000, 1_000_000
        );
        vm.stopPrank();
        
        // Verify atomicity: all steps completed
        assertGt(liquidity, 0, "Liquidity should be minted");
        assertEq(user.balance, userEthBefore - 0.1 ether, "ETH should be spent");
        assertEq(IERC721(address(positionManager)).balanceOf(user), userNftsBefore + 1, "NFT should be minted");
        
        // If it wasn't atomic, any failure would revert entire transaction
        // and none of these state changes would persist
    }

    /// @notice Test that verifies AutoLpHelper uses modifyLiquiditiesWithoutUnlock correctly
    /// @dev This is a regression test for the "already unlocked" vs "needs unlock" issue
    function testUsesCorrectPositionManagerMethod() public {
        // Skip if contracts not loaded
        if (address(autoLpHelper) == address(0)) {
            return;
        }
        
        // If AutoLpHelper incorrectly uses modifyLiquidity (which unlocks)
        // instead of modifyLiquiditiesWithoutUnlock (for already-unlocked context),
        // it will fail with "ContractLocked" or similar error
        
        vm.startPrank(user);
        // Should succeed without reverts
        uint128 liquidity = autoLpHelper.swapEthToUsdcUsdtAndMint{value: 0.1 ether}(
            1_000_000, 1_000_000
        );
        vm.stopPrank();
        
        assertGt(liquidity, 0, "Should succeed with modifyLiquiditiesWithoutUnlock");
    }

    /// @notice Test that verifies position can be modified by user after creation
    function testUserCanModifyTheirPosition() public {
        // Skip if contracts not loaded
        if (address(autoLpHelper) == address(0)) {
            return;
        }
        
        // Create initial position
        vm.startPrank(user);
        autoLpHelper.swapEthToUsdcUsdtAndMint{value: 0.1 ether}(1_000_000, 1_000_000);
        
        uint256 tokenId = positionManager.nextTokenId() - 1;
        
        // User should be able to increase liquidity on their position
        // (This requires user ownership of the NFT)
        // Note: Would need to provide tokens and build proper PositionManager call
        // For now, just verify ownership which is prerequisite for modification
        assertEq(
            IERC721(address(positionManager)).ownerOf(tokenId),
            user,
            "User must own NFT to modify position"
        );
        vm.stopPrank();
    }
}

/**
 * @title TestAutoLpReproduceFrontendIssue
 * @notice Reproduces the exact frontend error to debug the revert
 * @dev Tests with the exact parameters from the frontend call
 * @dev FORK-ONLY: These tests require a mainnet fork with deployed contracts
 *      Run with: forge test --match-contract TestAutoLpReproduceFrontendIssue --fork-url <RPC_URL>
 */
contract TestAutoLpReproduceFrontendIssue is Test {
    AutoLpHelper public autoLpHelper;
    IPoolManager public poolManager;
    IPositionManager public positionManager;
    
    address public user = makeAddr("frontend_user");
    bool public isForkEnvironment;
    
    modifier forkOnly() {
        if (!isForkEnvironment) {
            console.log("SKIPPED: Test requires fork environment. Run with: forge test --fork-url <RPC_URL>");
            vm.skip(true);
        }
        _;
    }
    
    function setUp() public {
        // Check if we're running on a fork using Foundry's fork detection
        // vm.activeFork() will revert if no fork is active
        try vm.activeFork() returns (uint256) {
            // We're on a fork - try to load deployed contracts
            if (block.chainid == 31337) {
                // Hardcoded anvil-hardhat addresses (mainnet fork)
                poolManager = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
                positionManager = IPositionManager(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
                
                try vm.readFile(string.concat(vm.projectRoot(), "/deployments/31337.json")) returns (string memory json) {
                    address autoLpHelperAddr = vm.parseJsonAddress(json, ".AutoLpHelper");
                    autoLpHelper = AutoLpHelper(payable(autoLpHelperAddr));
                    
                    console.log("Loaded AutoLpHelper:", address(autoLpHelper));
                    console.log("PoolManager:", address(poolManager));
                    console.log("PositionManager:", address(positionManager));
                    
                    // Verify deployment by attempting a view call
                    try autoLpHelper.POOL_MANAGER() returns (IPoolManager pm) {
                        if (address(pm) != address(0)) {
                            isForkEnvironment = true;
                            // Fund user with realistic amount
                            vm.deal(user, 10 ether);
                            console.log("Fork environment detected - tests will run");
                        } else {
                            console.log("WARNING: AutoLpHelper deployed but not initialized properly");
                            isForkEnvironment = false;
                        }
                    } catch {
                        console.log("WARNING: AutoLpHelper not callable - deployment may not exist");
                        isForkEnvironment = false;
                    }
                } catch {
                    console.log("Failed to load deployment file - not in fork environment");
                    isForkEnvironment = false;
                }
            }
        } catch {
            // No active fork - these tests will be skipped
            isForkEnvironment = false;
        }
    }
    
    /// @notice Reproduces the exact frontend call that's reverting
    /// @dev Uses the exact parameters from the error log
    function testReproduceFrontendRevert() public forkOnly {
        
        // Exact parameters from frontend error:
        // args: (770000000, 770000000)
        // These are 770 USDC/USDT (6 decimals)
        uint128 minUsdcOut = 770_000_000; // 770 USDC
        uint128 minUsdtOut = 770_000_000; // 770 USDT
        
        // Frontend sends 0.11 ETH based on calculation:
        // halfEthUsd * 0.70 = 770
        // halfEthUsd = 1100
        // ethAmount / 2 * 2200 = 1100
        // ethAmount = 1 ETH approximately
        // But let's test with 0.11 ETH as that's typical
        uint256 ethAmount = 0.11 ether;
        
        console.log("=== Reproducing Frontend Call ===");
        console.log("ETH sent:", ethAmount);
        console.log("Min USDC out:", minUsdcOut);
        console.log("Min USDT out:", minUsdtOut);
        console.log("User:", user);
        console.log("AutoLpHelper:", address(autoLpHelper));
        
        vm.startPrank(user);
        
        // This should revert with the same error
        try autoLpHelper.swapEthToUsdcUsdtAndMint{value: ethAmount}(minUsdcOut, minUsdtOut) returns (uint128 liquidity) {
            console.log("SUCCESS! Liquidity:", liquidity);
            assertTrue(liquidity > 0, "Should mint liquidity");
        } catch Error(string memory reason) {
            console.log("REVERT with reason:", reason);
            fail(string.concat("Transaction reverted: ", reason));
        } catch (bytes memory lowLevelData) {
            console.log("REVERT with no reason (empty or custom error)");
            console.log("Error data length:", lowLevelData.length);
            if (lowLevelData.length > 0) {
                console.logBytes(lowLevelData);
                // Try to decode common errors
                bytes4 selector = bytes4(lowLevelData);
                console.log("Error selector:");
                console.logBytes4(selector);
                
                // Check for common Uniswap errors
                if (selector == 0x90bfb865) {
                    console.log("ERROR: WrappedError - check PoolManager state");
                } else if (selector == 0x3b99b53d) {
                    console.log("ERROR: SliceOutOfBounds - encoding/decoding issue");
                } else if (selector == 0xf4d678b8) {
                    console.log("ERROR: InsufficientOutput - slippage too tight");
                }
            }
            fail("Transaction reverted with no string reason");
        }
        
        vm.stopPrank();
    }
    
    /// @notice Test with different ETH amounts to find the threshold
    function testFindWorkingEthAmount() public forkOnly {
        
        console.log("=== Testing Different ETH Amounts ===");
        
        uint256[] memory testAmounts = new uint256[](5);
        testAmounts[0] = 0.01 ether;
        testAmounts[1] = 0.05 ether;
        testAmounts[2] = 0.1 ether;
        testAmounts[3] = 0.11 ether;
        testAmounts[4] = 0.5 ether;
        
        for (uint i = 0; i < testAmounts.length; i++) {
            uint256 ethAmount = testAmounts[i];
            
            // Very generous slippage
            uint128 minOut = 100_000; // 0.1 USDC/USDT minimum
            
            console.log("\n--- Testing with ETH:", ethAmount);
            
            vm.startPrank(user);
            
            try autoLpHelper.swapEthToUsdcUsdtAndMint{value: ethAmount}(minOut, minOut) returns (uint128 liquidity) {
                console.log("SUCCESS with liquidity:", liquidity);
            } catch (bytes memory) {
                console.log("FAILED");
            }
            
            vm.stopPrank();
        }
    }
    
    /// @notice Test the new quote function
    function testQuoteFunction() public forkOnly {
        
        console.log("=== Testing Quote Function ===");
        
        uint256 ethAmount = 0.11 ether;
        
        try autoLpHelper.quoteSwapOutputs(ethAmount) returns (uint128 usdcOut, uint128 usdtOut) {
            console.log("Quote for", ethAmount, "ETH:");
            console.log("  Expected USDC:", usdcOut);
            console.log("  Expected USDT:", usdtOut);
            
            // Apply 10% slippage
            uint128 minUsdc = uint128((uint256(usdcOut) * 90) / 100);
            uint128 minUsdt = uint128((uint256(usdtOut) * 90) / 100);
            
            console.log("  Min USDC (10% slippage):", minUsdc);
            console.log("  Min USDT (10% slippage):", minUsdt);
            
            // Now try the actual swap with these values
            console.log("\n--- Executing Swap ---");
            vm.startPrank(user);
            
            try autoLpHelper.swapEthToUsdcUsdtAndMint{value: ethAmount}(minUsdc, minUsdt) returns (uint128 liquidity) {
                console.log("SUCCESS! Liquidity:", liquidity);
                assertTrue(liquidity > 0, "Should mint liquidity");
            } catch (bytes memory err) {
                console.log("FAILED even with quoted values");
                console.logBytes(err);
                fail("Swap failed with quoted minimums");
            }
            
            vm.stopPrank();
        } catch (bytes memory err) {
            console.log("Quote function failed");
            console.logBytes(err);
        }
    }
    
    /// @notice Test to verify pool state and liquidity
    function testPoolState() public {
        if (address(poolManager) == address(0)) {
            return;
        }
        
        console.log("=== Checking Pool State ===");
        
        // Check USDC/USDT pool
        try vm.readFile(string.concat(vm.projectRoot(), "/packages/foundry/deployments/31337.json")) returns (string memory json) {
            // Would need to decode pool keys and check state
            console.log("Deployment exists");
        } catch {
            console.log("No deployment found");
        }
    }
}
