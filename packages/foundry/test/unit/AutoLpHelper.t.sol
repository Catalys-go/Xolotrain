// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AutoLpHelper} from "../../contracts/AutoLpHelper.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract AutoLpHelperTest is Test {
    AutoLpHelper public autoLpHelper;
    
    address public mockPoolManager = address(0x1);
    address public mockPositionManager = address(0x2);
    address public mockHook = address(0x3);
    
    Currency public currency0 = Currency.wrap(address(0x1000));
    Currency public currency1 = Currency.wrap(address(0x2000));
    Currency public currency2 = Currency.wrap(address(0x3000));
    
    PoolKey public ethUsdcKey;
    PoolKey public ethUsdtKey;
    PoolKey public usdcUsdtKey;
    
    int24 public constant TICK_SPACING = 60;
    int24 public constant TICK_LOWER_OFFSET = -6;
    int24 public constant TICK_UPPER_OFFSET = 6;
    
    function setUp() public {
        // Create mock pool keys
        ethUsdcKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(mockHook)
        });
        
        ethUsdtKey = PoolKey({
            currency0: currency0,
            currency1: currency2,
            fee: 3000,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(mockHook)
        });
        
        usdcUsdtKey = PoolKey({
            currency0: currency1,
            currency1: currency2,
            fee: 500,
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
    
    // ============ Constructor & Immutables Tests ============
    
    function testConstructorSetsImmutables() public view {
        assertEq(address(autoLpHelper.POOL_MANAGER()), mockPoolManager, "PoolManager should match");
        assertEq(address(autoLpHelper.POSM()), mockPositionManager, "PositionManager should match");
        assertEq(autoLpHelper.TICK_SPACING(), TICK_SPACING, "TickSpacing should match");
        assertEq(autoLpHelper.TICK_LOWER_OFFSET(), TICK_LOWER_OFFSET, "TickLowerOffset should match");
        assertEq(autoLpHelper.TICK_UPPER_OFFSET(), TICK_UPPER_OFFSET, "TickUpperOffset should match");
    }
    
    function testConstructorSetsPoolKeys() public view {
        // Solidity generates tuple getters for public struct variables
        // Testing ETH_USDC key
        (Currency c0, Currency c1, uint24 fee, int24 tickSpacing,) = autoLpHelper.ethUsdcPoolKey();
        assertEq(Currency.unwrap(c0), Currency.unwrap(currency0));
        assertEq(Currency.unwrap(c1), Currency.unwrap(currency1));
        assertEq(fee, 3000);
        assertEq(tickSpacing, TICK_SPACING);
        
        // Testing ETH_USDT key
        (c0, c1,,,) = autoLpHelper.ethUsdtPoolKey();
        assertEq(Currency.unwrap(c0), Currency.unwrap(currency0));
        assertEq(Currency.unwrap(c1), Currency.unwrap(currency2));
        
        // Testing USDC_USDT key
        (c0, c1, fee,,) = autoLpHelper.usdcUsdtPoolKey();
        assertEq(Currency.unwrap(c0), Currency.unwrap(currency1));
        assertEq(Currency.unwrap(c1), Currency.unwrap(currency2));
        assertEq(fee, 500);
    }
    
    // ============ Receive Function Tests ============
    
    function testReceiveEther() public {
        // Contract should be able to receive ETH
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        
        (bool success,) = address(autoLpHelper).call{value: amount}("");
        assertTrue(success, "Should be able to receive ETH");
        assertEq(address(autoLpHelper).balance, amount, "Contract balance should match");
    }
    
    function testReceiveMultipleEtherDeposits() public {
        vm.deal(address(this), 10 ether);
        
        // Send ETH multiple times
        (bool success1,) = address(autoLpHelper).call{value: 1 ether}("");
        (bool success2,) = address(autoLpHelper).call{value: 2 ether}("");
        (bool success3,) = address(autoLpHelper).call{value: 3 ether}("");
        
        assertTrue(success1 && success2 && success3, "All transfers should succeed");
        assertEq(address(autoLpHelper).balance, 6 ether, "Contract should have 6 ETH");
    }
    
    // ============ Validation Tests ============
    
    function testTickOffsetRelationship() public view {
        // Tick offsets should be symmetric (lower is negative, upper is positive)
        int24 tickLower = autoLpHelper.TICK_LOWER_OFFSET();
        int24 tickUpper = autoLpHelper.TICK_UPPER_OFFSET();
        
        assertTrue(tickLower < 0, "Lower offset should be negative");
        assertTrue(tickUpper > 0, "Upper offset should be positive");
        assertEq(tickLower, -tickUpper, "Offsets should be symmetric");
    }
    
    // ============ Pool Key Currency Tests ============
    
    function testEthUsdcCurrencyOrder() public view {
        (Currency c0, Currency c1,,,) = autoLpHelper.ethUsdcPoolKey();
        
        // Verify currency0 < currency1 (Uniswap v4 requirement)
        assertTrue(
            Currency.unwrap(c0) < Currency.unwrap(c1),
            "currency0 should be less than currency1"
        );
    }
    
    function testEthUsdtCurrencyOrder() public view {
        (Currency c0, Currency c1,,,) = autoLpHelper.ethUsdtPoolKey();
        
        assertTrue(
            Currency.unwrap(c0) < Currency.unwrap(c1),
            "currency0 should be less than currency1"
        );
    }
    
    function testUsdcUsdtCurrencyOrder() public view {
        (Currency c0, Currency c1,,,) = autoLpHelper.usdcUsdtPoolKey();
        
        assertTrue(
            Currency.unwrap(c0) < Currency.unwrap(c1),
            "currency0 should be less than currency1"
        );
    }
    
    // ============ Tick Spacing Validation ============
    
    function testTickSpacingMustBePositive() public view {
        assertTrue(autoLpHelper.TICK_SPACING() > 0, "Tick spacing must be positive");
    }
    
    // ============ Address Validation Tests ============
    
    function testContractHasNonZeroAddress() public view {
        assertTrue(address(autoLpHelper) != address(0), "Contract should have valid address");
    }
    
    function testPoolManagerIsSet() public view {
        assertTrue(
            address(autoLpHelper.POOL_MANAGER()) != address(0),
            "PoolManager should be set"
        );
    }
    
    function testPositionManagerIsSet() public view {
        assertTrue(
            address(autoLpHelper.POSM()) != address(0),
            "PositionManager should be set"
        );
    }
}
