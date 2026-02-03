// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title AutoLpHelper
/// @notice Atomically swaps ETH to USDC/USDT and creates LP position in one transaction
/// @dev Uses IUnlockCallback pattern for atomic execution
contract AutoLpHelper is IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    error ZeroInput();
    error UnauthorizedCaller();
    error InsufficientOutput(uint256 expected, uint256 actual);

    event PositionCreated(
        address indexed owner,
        uint256 ethInput,
        uint256 usdcAmount,
        uint256 usdtAmount,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 timestamp
    );

    IPoolManager public immutable poolManager;
    IPositionManager public immutable posm;
    
    PoolKey public ethUsdcPoolKey;
    PoolKey public ethUsdtPoolKey;
    PoolKey public usdcUsdtPoolKey;

    int24 public immutable tickSpacing;
    int24 public immutable tickLowerOffset;
    int24 public immutable tickUpperOffset;

    uint256 public constant DEFAULT_SLIPPAGE_BPS = 200;

    struct SwapAndMintParams {
        uint128 ethForUsdc;
        uint128 ethForUsdt;
        uint128 minUsdcOut;
        uint128 minUsdtOut;
        int24 tickLower;
        int24 tickUpper;
        address recipient;
    }

    constructor(
        IPoolManager _poolManager,
        IPositionManager _posm,
        PoolKey memory _ethUsdcPoolKey,
        PoolKey memory _ethUsdtPoolKey,
        PoolKey memory _usdcUsdtPoolKey,
        int24 _tickSpacing,
        int24 _tickLowerOffset,
        int24 _tickUpperOffset
    ) {
        poolManager = _poolManager;
        posm = _posm;
        ethUsdcPoolKey = _ethUsdcPoolKey;
        ethUsdtPoolKey = _ethUsdtPoolKey;
        usdcUsdtPoolKey = _usdcUsdtPoolKey;
        tickSpacing = _tickSpacing;
        tickLowerOffset = _tickLowerOffset;
        tickUpperOffset = _tickUpperOffset;
    }

    receive() external payable {}

    /// @notice Swaps ETH to USDC/USDT and creates an LP position in one atomic transaction
    /// @return liquidity The liquidity amount of the created position
    function swapEthToUsdcUsdtAndMint()
        external
        payable
        returns (uint128 liquidity)
    {
        if (msg.value == 0) revert ZeroInput();

        // Calculate swap amounts
        uint128 half = uint128(msg.value / 2);
        uint128 remainder = uint128(msg.value) - half;

        // Get current prices for slippage calculation
        (uint160 sqrtPriceEthUsdc,,,) = StateLibrary.getSlot0(poolManager, ethUsdcPoolKey.toId());
        (uint160 sqrtPriceEthUsdt,,,) = StateLibrary.getSlot0(poolManager, ethUsdtPoolKey.toId());
        (uint160 sqrtPriceUsdcUsdt, int24 tickCurrent,,) = StateLibrary.getSlot0(poolManager, usdcUsdtPoolKey.toId());

        // Calculate expected outputs with slippage
        uint128 minUsdcOut = _applySlippage(_spotQuote(half, sqrtPriceEthUsdc, true));
        uint128 minUsdtOut = _applySlippage(_spotQuote(remainder, sqrtPriceEthUsdt, true));

        // Calculate tick range for LP position
        int24 tickLower = _alignTick(tickCurrent + tickLowerOffset);
        int24 tickUpper = _alignTick(tickCurrent + tickUpperOffset);

        SwapAndMintParams memory params = SwapAndMintParams({
            ethForUsdc: half,
            ethForUsdt: remainder,
            minUsdcOut: minUsdcOut,
            minUsdtOut: minUsdtOut,
            tickLower: tickLower,
            tickUpper: tickUpper,
            recipient: msg.sender
        });

        // Execute atomically via unlock callback
        bytes memory result = poolManager.unlock(abi.encode(params));
        liquidity = abi.decode(result, (uint128));

        emit PositionCreated(
            msg.sender,
            msg.value,
            minUsdcOut,
            minUsdtOut,
            tickLower,
            tickUpper,
            liquidity,
            block.timestamp
        );
    }

    /// @notice Callback function called by PoolManager.unlock()
    /// @dev All swaps and LP minting happen atomically here
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert UnauthorizedCaller();

        SwapAndMintParams memory params = abi.decode(data, (SwapAndMintParams));

        // Step 1: Swap ETH → USDC
        BalanceDelta delta1 = poolManager.swap(
            ethUsdcPoolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(uint256(params.ethForUsdc)),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            bytes("")
        );

        // Step 2: Swap ETH → USDT
        BalanceDelta delta2 = poolManager.swap(
            ethUsdtPoolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(uint256(params.ethForUsdt)),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            bytes("")
        );

        // Check slippage
        uint256 usdcReceived = uint256(uint128(delta1.amount1()));
        uint256 usdtReceived = uint256(uint128(delta2.amount1()));
        
        if (usdcReceived < params.minUsdcOut) {
            revert InsufficientOutput(params.minUsdcOut, usdcReceived);
        }
        if (usdtReceived < params.minUsdtOut) {
            revert InsufficientOutput(params.minUsdtOut, usdtReceived);
        }

        // Step 3: Calculate liquidity for LP position
        (uint160 sqrtPrice,,,) = StateLibrary.getSlot0(poolManager, usdcUsdtPoolKey.toId());
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPrice,
            TickMath.getSqrtPriceAtTick(params.tickLower),
            TickMath.getSqrtPriceAtTick(params.tickUpper),
            usdcReceived,
            usdtReceived
        );

        // Step 4: Mint LP position directly via poolManager
        (BalanceDelta delta3,) = poolManager.modifyLiquidity(
            usdcUsdtPoolKey,
            ModifyLiquidityParams({
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: bytes32(0)
            }),
            bytes("")
        );

        // Step 5: Settle all deltas
        // Settle ETH from swaps - we owe ETH to the pool
        _settle(ethUsdcPoolKey.currency0, uint256(uint128(-delta1.amount0())));
        _settle(ethUsdtPoolKey.currency0, uint256(uint128(-delta2.amount0())));
        
        // For USDC/USDT: the swaps gave us positive deltas (we're owed tokens)
        // and modifyLiquidity gave us negative deltas (we owe tokens)
        // In an ideal world, these would cancel out exactly
        // But there might be small differences, so we need to handle both cases
        
        // Net USDC delta = what we got from swap1 + what we owe from LP mint
        int256 netUsdcDelta = int256(int128(delta1.amount1())) + int256(int128(delta3.amount0()));
        // Net USDT delta = what we got from swap2 + what we owe from LP mint  
        int256 netUsdtDelta = int256(int128(delta2.amount1())) + int256(int128(delta3.amount1()));
        
        // Settle or take based on net position
        if (netUsdcDelta < 0) {
            // We owe USDC - need to transfer to poolManager
            // But we don't have it yet! Take from the swap first, then settle
            poolManager.take(usdcUsdtPoolKey.currency0, address(this), uint128(int128(delta1.amount1())));
            IERC20(Currency.unwrap(usdcUsdtPoolKey.currency0)).transfer(address(poolManager), uint256(-netUsdcDelta));
            poolManager.settle();
        } else if (netUsdcDelta > 0) {
            // We're owed USDC - send to recipient
            poolManager.take(usdcUsdtPoolKey.currency0, params.recipient, uint256(netUsdcDelta));
        }
        
        if (netUsdtDelta < 0) {
            // We owe USDT
            poolManager.take(usdcUsdtPoolKey.currency1, address(this), uint128(int128(delta2.amount1())));
            IERC20(Currency.unwrap(usdcUsdtPoolKey.currency1)).transfer(address(poolManager), uint256(-netUsdtDelta));
            poolManager.settle();
        } else if (netUsdtDelta > 0) {
            // We're owed USDT
            poolManager.take(usdcUsdtPoolKey.currency1, params.recipient, uint256(netUsdtDelta));
        }

        return abi.encode(liquidity);
    }

    /// @notice Settle currency delta with PoolManager
    function _settle(Currency currency, uint256 amount) internal {
        if (currency.isAddressZero()) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            // Note: For ERC20 tokens, would need to transfer first
            poolManager.settle();
        }
    }

    /// @notice Calculate spot quote for a swap
    function _spotQuote(uint128 amountIn, uint160 sqrtPriceX96, bool zeroForOne) internal pure returns (uint128) {
        if (zeroForOne) {
            uint256 intermediate = FullMath.mulDiv(amountIn, sqrtPriceX96, FixedPoint96.Q96);
            uint256 amountOut = FullMath.mulDiv(intermediate, sqrtPriceX96, FixedPoint96.Q96);
            return uint128(amountOut);
        } else {
            uint256 intermediate = FullMath.mulDiv(amountIn, FixedPoint96.Q96, sqrtPriceX96);
            uint256 amountOut = FullMath.mulDiv(intermediate, FixedPoint96.Q96, sqrtPriceX96);
            return uint128(amountOut);
        }
    }

    /// @notice Apply slippage tolerance to expected output
    function _applySlippage(uint128 amountOut) internal pure returns (uint128) {
        uint256 adjusted = (uint256(amountOut) * (10_000 - DEFAULT_SLIPPAGE_BPS)) / 10_000;
        return uint128(adjusted);
    }

    /// @notice Align tick to tick spacing
    function _alignTick(int24 tick) internal view returns (int24 aligned) {
        int24 spacing = tickSpacing;
        int24 compressed = tick / spacing;
        aligned = compressed * spacing;
    }
}
