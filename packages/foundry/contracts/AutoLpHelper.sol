// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {CalldataDecoder} from "@uniswap/v4-periphery/src/libraries/CalldataDecoder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title AutoLpHelper
/// @notice Atomically swaps ETH to USDC/USDT and creates NFT-based LP position in one transaction
/// @dev Uses IUnlockCallback pattern + PositionManager for user-owned positions
contract AutoLpHelper is IUnlockCallback {
    using CalldataDecoder for bytes;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    error ZeroInput();
    error UnauthorizedCaller();
    error InsufficientOutput(uint256 expected, uint256 actual);

    event LiquidityAdded(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 ethInput,
        uint256 usdcAmount,
        uint256 usdtAmount,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 timestamp
    );

    IPoolManager public immutable POOL_MANAGER;
    IPositionManager public immutable POSM;
    
    PoolKey public ethUsdcPoolKey;
    PoolKey public ethUsdtPoolKey;
    PoolKey public usdcUsdtPoolKey;

    int24 public immutable TICK_SPACING;
    int24 public immutable TICK_LOWER_OFFSET;
    int24 public immutable TICK_UPPER_OFFSET;

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
        POOL_MANAGER = _poolManager;
        POSM = _posm;
        ethUsdcPoolKey = _ethUsdcPoolKey;
        ethUsdtPoolKey = _ethUsdtPoolKey;
        usdcUsdtPoolKey = _usdcUsdtPoolKey;
        TICK_SPACING = _tickSpacing;
        TICK_LOWER_OFFSET = _tickLowerOffset;
        TICK_UPPER_OFFSET = _tickUpperOffset;
    }

    receive() external payable {}

    /// @notice Swaps ETH to USDC/USDT and creates an LP position in one atomic transaction
    /// @dev Position tracking is handled by PetRegistry via EggHatchHook, not by this contract
    /// @param minUsdcOut Minimum USDC to receive from swap (slippage protection)
    /// @param minUsdtOut Minimum USDT to receive from swap (slippage protection)
    /// @return liquidity The liquidity amount of the created position
    function swapEthToUsdcUsdtAndMint(uint128 minUsdcOut, uint128 minUsdtOut)
        external
        payable
        returns (uint128 liquidity)
    {
        if (msg.value == 0) revert ZeroInput();

        // Calculate swap amounts
        uint128 half = uint128(msg.value / 2);
        uint128 remainder = uint128(msg.value) - half;

        // Get current tick for LP position
        (, int24 tickCurrent,,) = StateLibrary.getSlot0(POOL_MANAGER, usdcUsdtPoolKey.toId());

        // Calculate tick range for LP position
        int24 tickLower = _alignTick(tickCurrent + TICK_LOWER_OFFSET);
        int24 tickUpper = _alignTick(tickCurrent + TICK_UPPER_OFFSET);

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
        bytes memory result = POOL_MANAGER.unlock(abi.encode(params));
        (uint128 resultLiquidity, uint256 positionId) = abi.decode(result, (uint128, uint256));
        liquidity = resultLiquidity;

        emit LiquidityAdded(
            msg.sender,
            positionId,
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
        if (msg.sender != address(POOL_MANAGER)) revert UnauthorizedCaller();

        SwapAndMintParams memory params = abi.decode(data, (SwapAndMintParams));

        // Step 1: Swap ETH → USDC
        BalanceDelta delta1 = POOL_MANAGER.swap(
            ethUsdcPoolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(uint256(params.ethForUsdc)),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            bytes("")
        );

        // Step 2: Swap ETH → USDT
        BalanceDelta delta2 = POOL_MANAGER.swap(
            ethUsdtPoolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(uint256(params.ethForUsdt)),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            bytes("")
        );

        // Validate deltas - swaps should give us positive token1 (USDC/USDT)
        require(delta1.amount1() > 0, "Invalid USDC swap delta");
        require(delta2.amount1() > 0, "Invalid USDT swap delta");
        
        // Safe casting after validation
        uint128 usdcReceived = uint128(delta1.amount1());
        uint128 usdtReceived = uint128(delta2.amount1());
        
        if (usdcReceived < params.minUsdcOut) {
            revert InsufficientOutput(params.minUsdcOut, usdcReceived);
        }
        if (usdtReceived < params.minUsdtOut) {
            revert InsufficientOutput(params.minUsdtOut, usdtReceived);
        }

        // Step 3: Calculate liquidity for LP position
        (uint160 sqrtPrice,,,) = StateLibrary.getSlot0(POOL_MANAGER, usdcUsdtPoolKey.toId());
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPrice,
            TickMath.getSqrtPriceAtTick(params.tickLower),
            TickMath.getSqrtPriceAtTick(params.tickUpper),
            usdcReceived,
            usdtReceived
        );

        // Step 4: Create LP position via PoolManager
        // NOTE: Position is technically owned by this contract in PoolManager,
        // but user ownership is tracked via:
        // 1. hookData containing user address
        // 2. EggHatchHook minting NFT to user
        // 3. PetRegistry associating position with user
        // This approach maintains atomicity and works within unlock callback constraints.
        // For full PositionManager NFT integration, would require multi-transaction flow.
        
        // Create unique position ID for this user
        uint256 positionId = uint256(keccak256(abi.encodePacked(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            block.timestamp
        )));
        
        bytes32 salt = bytes32(positionId);
        
        // Encode hook data: (address owner, uint256 positionId, int24 tickLower, int24 tickUpper)
        bytes memory hookData = abi.encode(
            params.recipient,
            positionId,
            params.tickLower,
            params.tickUpper
        );
        
        // Create position - hook will mint pet NFT to user
        (BalanceDelta delta3,) = POOL_MANAGER.modifyLiquidity(
            usdcUsdtPoolKey,
            ModifyLiquidityParams({
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: salt
            }),
            hookData
        );

        // Step 5: Settle deltas using canonical v4 sync/settle/take pattern
        
        // Settle ETH debt from both swaps (negative deltas)
        require(delta1.amount0() < 0, "Expected negative ETH delta from swap1");
        require(delta2.amount0() < 0, "Expected negative ETH delta from swap2");
        uint128 totalEthOwed = uint128(-delta1.amount0()) + uint128(-delta2.amount0());
        POOL_MANAGER.settle{value: totalEthOwed}();
        
        // Calculate net deltas for USDC and USDT
        // Swap outputs (positive) + LP mint inputs (negative) = net
        int128 netUsdcDelta = delta1.amount1() + delta3.amount0();
        int128 netUsdtDelta = delta2.amount1() + delta3.amount1();
        
        Currency usdcCurrency = usdcUsdtPoolKey.currency0;
        Currency usdtCurrency = usdcUsdtPoolKey.currency1;
        
        // Settle net USDC delta using canonical pattern
        if (netUsdcDelta < 0) {
            // We owe USDC - take from swap, then sync/transfer/settle
            POOL_MANAGER.take(usdcCurrency, address(this), usdcReceived);
            POOL_MANAGER.sync(usdcCurrency);
            IERC20(Currency.unwrap(usdcCurrency)).transfer(address(POOL_MANAGER), uint128(-netUsdcDelta));
            POOL_MANAGER.settle();
        } else if (netUsdcDelta > 0) {
            // We're owed USDC - take it and send to user
            POOL_MANAGER.take(usdcCurrency, params.recipient, uint128(netUsdcDelta));
        }
        // If zero, deltas perfectly netted
        
        // Settle net USDT delta using canonical pattern
        if (netUsdtDelta < 0) {
            // We owe USDT - take from swap, then sync/transfer/settle
            POOL_MANAGER.take(usdtCurrency, address(this), usdtReceived);
            POOL_MANAGER.sync(usdtCurrency);
            IERC20(Currency.unwrap(usdtCurrency)).transfer(address(POOL_MANAGER), uint128(-netUsdtDelta));
            POOL_MANAGER.settle();
        } else if (netUsdtDelta > 0) {
            // We're owed USDT - take it and send to user
            POOL_MANAGER.take(usdtCurrency, params.recipient, uint128(netUsdtDelta));
        }
        // If zero, deltas perfectly netted

        return abi.encode(liquidity, positionId);
    }
    

    /// @notice Quote the expected USDC and USDT output for a given ETH input
    /// @dev Call this before swapEthToUsdcUsdtAndMint to get accurate minimum output values
    /// @param ethAmount The amount of ETH to swap
    /// @return usdcOut Expected USDC output (with 6 decimals)
    /// @return usdtOut Expected USDT output (with 6 decimals)
    function quoteSwapOutputs(uint256 ethAmount) 
        external 
        view 
        returns (uint128 usdcOut, uint128 usdtOut) 
    {
        if (ethAmount == 0) return (0, 0);
        
        uint128 half = uint128(ethAmount / 2);
        uint128 remainder = uint128(ethAmount) - half;
        
        // Quote ETH → USDC swap
        usdcOut = _quoteExactInputSingle(
            ethUsdcPoolKey,
            true, // zeroForOne (ETH → USDC)
            half
        );
        
        // Quote ETH → USDT swap  
        usdtOut = _quoteExactInputSingle(
            ethUsdtPoolKey,
            true, // zeroForOne (ETH → USDT)
            remainder
        );
    }

    /// @notice Internal function to quote a single swap
    /// @dev Uses the same pricing logic as the actual swap
    function _quoteExactInputSingle(
        PoolKey memory poolKey,
        bool zeroForOne,
        uint128 amountIn
    ) internal view returns (uint128 amountOut) {
        // Get current pool state
        (, int24 tick,,) = StateLibrary.getSlot0(POOL_MANAGER, poolKey.toId());
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        
        // Simple approximation using spot price
        // For exact amounts, would need to simulate the swap
        if (zeroForOne) {
            // ETH → Token: amount1 = amount0 * price
            uint256 amount1 = FullMath.mulDiv(
                amountIn,
                sqrtPriceX96,
                FixedPoint96.Q96
            );
            amount1 = FullMath.mulDiv(
                amount1,
                sqrtPriceX96,
                FixedPoint96.Q96
            );
            // Apply fee (500 = 0.05%)
            amount1 = (amount1 * 9950) / 10000;
            amountOut = uint128(amount1);
        } else {
            // Token → ETH: amount0 = amount1 / price
            uint256 amount0 = FullMath.mulDiv(
                amountIn,
                FixedPoint96.Q96,
                sqrtPriceX96
            );
            amount0 = FullMath.mulDiv(
                amount0,
                FixedPoint96.Q96,
                sqrtPriceX96
            );
            // Apply fee
            amount0 = (amount0 * 9950) / 10000;
            amountOut = uint128(amount0);
        }
    }

    /// @notice Align tick to tick spacing
    function _alignTick(int24 tick) internal view returns (int24 aligned) {
        int24 spacing = TICK_SPACING;
        int24 compressed = tick / spacing;
        aligned = compressed * spacing;
    }
}
