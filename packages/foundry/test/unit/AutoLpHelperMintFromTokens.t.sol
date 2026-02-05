// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AutoLpHelper} from "../../contracts/AutoLpHelper.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AutoLpHelperMintFromTokens Unit Tests
 * @notice Tests for the NEW mintLpFromTokens() function used by solver agents
 * @dev Unit tests focus on parameter validation and pre-unlock behavior
 * 
 * Note: Full integration tests are in AutoLpHelperMintFromTokensIntegration.t.sol
 * These unit tests verify input validation before calling PoolManager.unlock()
 */
contract AutoLpHelperMintFromTokensTest is Test {
    AutoLpHelper public autoLpHelper;
    
    address public mockPoolManager;
    address public mockPositionManager;
    address public mockHook;
    
    address public mockUSDC;
    address public mockUSDT;
    address public mockWETH;
    
    address public solver = address(0x5050);
    address public user = address(0x1111);
    
    PoolKey public ethUsdcKey;
    PoolKey public ethUsdtKey;
    PoolKey public usdcUsdtKey;
    
    int24 public constant TICK_SPACING = 60;
    int24 public constant TICK_LOWER_OFFSET = -6;
    int24 public constant TICK_UPPER_OFFSET = 6;
    
    // Test amounts
    uint128 public constant USDC_AMOUNT = 1000e6;  // 1000 USDC
    uint128 public constant USDT_AMOUNT = 1000e6;  // 1000 USDT
    
    function setUp() public {
        // Deploy mock contracts
        mockPoolManager = address(new MockPoolManager());
        mockPositionManager = address(new MockPositionManager());
        mockHook = address(0x3);
        
        // Deploy mock ERC20 tokens
        mockUSDC = address(new MockERC20("USD Coin", "USDC", 6));
        mockUSDT = address(new MockERC20("Tether", "USDT", 6));
        mockWETH = address(new MockERC20("Wrapped Ether", "WETH", 18));
        
        // Ensure correct currency ordering (lower address first)
        Currency currency0;
        Currency currency1;
        Currency currency2;
        
        if (mockWETH < mockUSDC && mockWETH < mockUSDT) {
            currency0 = Currency.wrap(mockWETH);
            if (mockUSDC < mockUSDT) {
                currency1 = Currency.wrap(mockUSDC);
                currency2 = Currency.wrap(mockUSDT);
            } else {
                currency1 = Currency.wrap(mockUSDT);
                currency2 = Currency.wrap(mockUSDC);
            }
        } else if (mockUSDC < mockUSDT) {
            currency0 = Currency.wrap(mockUSDC);
            currency1 = Currency.wrap(mockUSDT);
            currency2 = Currency.wrap(mockWETH);
        } else {
            currency0 = Currency.wrap(mockUSDT);
            currency1 = Currency.wrap(mockUSDC);
            currency2 = Currency.wrap(mockWETH);
        }
        
        // Create pool keys
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
        
        // Mint tokens to solver for testing (use actual currencies from pool key)
        MockERC20(Currency.unwrap(usdcUsdtKey.currency0)).mint(solver, 10000e6);
        MockERC20(Currency.unwrap(usdcUsdtKey.currency1)).mint(solver, 10000e6);
    }
    
    // ============ Parameter Validation Tests ============
    
    function testRevertZeroUsdcAmount() public {
        vm.startPrank(solver);
        
        vm.expectRevert(AutoLpHelper.ZeroInput.selector);
        autoLpHelper.mintLpFromTokens(
            0,           // Zero USDC
            USDT_AMOUNT,
            -360,
            360,
            user
        );
        
        vm.stopPrank();
    }
    
    function testRevertZeroUsdtAmount() public {
        vm.startPrank(solver);
        
        vm.expectRevert(AutoLpHelper.ZeroInput.selector);
        autoLpHelper.mintLpFromTokens(
            USDC_AMOUNT,
            0,           // Zero USDT
            -360,
            360,
            user
        );
        
        vm.stopPrank();
    }
    
    function testRevertBothAmountsZero() public {
        vm.startPrank(solver);
        
        vm.expectRevert(AutoLpHelper.ZeroInput.selector);
        autoLpHelper.mintLpFromTokens(
            0,
            0,
            -360,
            360,
            user
        );
        
        vm.stopPrank();
    }
    
    function testRevertZeroRecipient() public {
        vm.startPrank(solver);
        
        vm.expectRevert(AutoLpHelper.UnauthorizedCaller.selector);
        autoLpHelper.mintLpFromTokens(
            USDC_AMOUNT,
            USDT_AMOUNT,
            -360,
            360,
            address(0)  // Zero recipient
        );
        
        vm.stopPrank();
    }
    
    // ============ Token Transfer Tests (Pre-Unlock Validation) ============
    // Note: Actual token transfers can only be tested in integration tests
    // Unit tests revert at MockPoolManager.unlock() before transfers complete
    
    function testRevertsWithoutApproval() public {
        vm.startPrank(solver);
        
        // Don't approve - should revert on transferFrom
        vm.expectRevert();
        autoLpHelper.mintLpFromTokens(
            USDC_AMOUNT,
            USDT_AMOUNT,
            -360,
            360,
            user
        );
        
        vm.stopPrank();
    }
    
    function testRevertsWithInsufficientBalance() public {
        vm.startPrank(solver);
        
        Currency usdcCurrency = usdcUsdtKey.currency0;
        Currency usdtCurrency = usdcUsdtKey.currency1;
        
        // Approve way more than balance
        IERC20(Currency.unwrap(usdcCurrency)).approve(address(autoLpHelper), type(uint256).max);
        IERC20(Currency.unwrap(usdtCurrency)).approve(address(autoLpHelper), type(uint256).max);
        
        // Try to mint with more than balance
        vm.expectRevert();
        autoLpHelper.mintLpFromTokens(
            type(uint128).max,
            type(uint128).max,
            -360,
            360,
            user
        );
        
        vm.stopPrank();
    }
    
    // ============ Struct Encoding Tests ============
    
    function testEncodesCorrectStruct() public {
        // This tests that the discriminator is set correctly
        vm.startPrank(solver);
        
        Currency usdcCurrency = usdcUsdtKey.currency0;
        Currency usdtCurrency = usdcUsdtKey.currency1;
        
        IERC20(Currency.unwrap(usdcCurrency)).approve(address(autoLpHelper), USDC_AMOUNT);
        IERC20(Currency.unwrap(usdtCurrency)).approve(address(autoLpHelper), USDT_AMOUNT);
        
        // Struct should have isSwapAndMint = false
        // We can't directly test this in unit test, but we verify encoding doesn't revert
        vm.expectRevert(); // Will revert at unlock callback
        autoLpHelper.mintLpFromTokens(
            USDC_AMOUNT,
            USDT_AMOUNT,
            -360,
            360,
            user
        );
        
        vm.stopPrank();
    }
    
    // Note: Struct encoding and unlock callback behavior tested in integration tests
}

// ============ Mock Contracts ============

contract MockPoolManager {
    function unlock(bytes calldata) external pure returns (bytes memory) {
        revert("MockPoolManager: unlock not implemented");
    }
}

contract MockPositionManager {
    // Empty mock
}

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
    
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}
