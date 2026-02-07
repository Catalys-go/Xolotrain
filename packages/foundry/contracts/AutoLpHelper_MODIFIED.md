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

// Simple interface for PetRegistry - avoids circular dependency
interface PetRegistry {
    function pets(uint256 petId) external view returns (
        address owner,
        uint256 health,
        uint256 birthBlock,
        uint256 lastUpdate,
        uint256 chainId,
        bytes32 poolId,
        uint256 positionId
    );
}

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

    event IntentCreated(
        bytes32 indexed compactId,
        uint256 indexed petId,
        address indexed user,
        uint256 sourceChainId,
        uint256 destinationChainId,
        uint128 usdcAmount,
        uint128 usdtAmount,
        int24 tickLower,
        int24 tickUpper,
        uint256 timestamp
    );

    event LPCreatedFromIntent(
        bytes32 indexed compactId,
        uint256 indexed positionId,
        address indexed solver,
        uint256 chainId,
        uint128 liquidity,
        uint256 timestamp
    );

    IPoolManager public immutable POOL_MANAGER;
    IPositionManager public immutable POSM;
    
    // Reference to PetRegistry for ownership verification
    address public petRegistry;
    
    PoolKey public ethUsdcPoolKey;
    PoolKey public ethUsdtPoolKey;
    PoolKey public usdcUsdtPoolKey;

    int24 public immutable TICK_SPACING;
    int24 public immutable TICK_LOWER_OFFSET;
    int24 public immutable TICK_UPPER_OFFSET;

    uint256 public constant DEFAULT_SLIPPAGE_BPS = 200;

    // ✅ MODIFIED: Added petId to struct
    struct SwapAndMintParams {
        bool isSwapAndMint; // Discriminator: true for swap, false for others
        bool isSingleToken; // Discriminator: false for this type
        uint256 petId; // ✅ NEW: Pet ID (0 for new pet)
        uint128 ethForUsdc;
        uint128 ethForUsdt;
        uint128 minUsdcOut;
        uint128 minUsdtOut;
        int24 tickLower;
        int24 tickUpper;
        address recipient;
    }

    // ✅ MODIFIED: Added petId to struct
    struct MintFromTokensParams {
        bool isSwapAndMint; // Discriminator: always false
        bool isSingleToken; // Discriminator: false for dual-token
        uint256 petId; // ✅ NEW: Pet ID (0 for new pet)
        uint128 usdcAmount;
        uint128 usdtAmount;
        int24 tickLower;
        int24 tickUpper;
        address recipient;
    }

    // ✅ NEW: Struct for USDC-only minting
    struct MintFromUsdcOnlyParams {
        bool isSwapAndMint; // Discriminator: always false
        bool isSingleToken; // Discriminator: true for single-token
        uint256 petId; // ✅ Pet ID for migration
        uint256 usdcAmount; // ✅ Total USDC (will split)
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

    function setPetRegistry(address _petRegistry) external {
        require(petRegistry == address(0), "Registry already set");
        require(_petRegistry != address(0), "Invalid registry");
        petRegistry = _petRegistry;
    }

    receive() external payable {}

    function swapEthToUsdcUsdtAndMint(uint128 minUsdcOut, uint128 minUsdtOut)
        external
        payable
        returns (uint128 liquidity)
    {
        if (msg.value == 0) revert ZeroInput();

        uint128 half = uint128(msg.value / 2);
        uint128 remainder = uint128(msg.value) - half;

        (, int24 tickCurrent,,) = StateLibrary.getSlot0(POOL_MANAGER, usdcUsdtPoolKey.toId());

        int24 tickLower = _alignTick(tickCurrent + TICK_LOWER_OFFSET);
        int24 tickUpper = _alignTick(tickCurrent + TICK_UPPER_OFFSET);

        SwapAndMintParams memory params = SwapAndMintParams({
            isSwapAndMint: true,
            isSingleToken: false,
            petId: 0, // ✅ NEW: 0 = new pet
            ethForUsdc: half,
            ethForUsdt: remainder,
            minUsdcOut: minUsdcOut,
            minUsdtOut: minUsdtOut,
            tickLower: tickLower,
            tickUpper: tickUpper,
            recipient: msg.sender
        });

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

    /// @notice ✅ MODIFIED: Added petId parameter
    function mintLpFromTokens(
        uint256 petId, // ✅ NEW
        uint128 usdcAmount,
        uint128 usdtAmount,
        int24 tickLower,
        int24 tickUpper,
        address recipient
    ) external returns (uint256 positionId) {
        if (usdcAmount == 0 || usdtAmount == 0) revert ZeroInput();
        if (recipient == address(0)) revert UnauthorizedCaller();

        tickLower = _alignTick(tickLower);
        tickUpper = _alignTick(tickUpper);

        Currency usdcCurrency = usdcUsdtPoolKey.currency0;
        Currency usdtCurrency = usdcUsdtPoolKey.currency1;
        
        IERC20(Currency.unwrap(usdcCurrency)).transferFrom(msg.sender, address(this), usdcAmount);
        IERC20(Currency.unwrap(usdtCurrency)).transferFrom(msg.sender, address(this), usdtAmount);

        MintFromTokensParams memory params = MintFromTokensParams({
            isSwapAndMint: false,
            isSingleToken: false,
            petId: petId, // ✅ NEW
            usdcAmount: usdcAmount,
            usdtAmount: usdtAmount,
            tickLower: tickLower,
            tickUpper: tickUpper,
            recipient: recipient
        });

        bytes memory result = POOL_MANAGER.unlock(abi.encode(params));
        (uint128 liquidity, uint256 returnedPositionId) = abi.decode(result, (uint128, uint256));
        positionId = returnedPositionId;

        emit LiquidityAdded(
            recipient,
            positionId,
            0,
            usdcAmount,
            usdtAmount,
            tickLower,
            tickUpper,
            liquidity,
            block.timestamp
        );
    }

    /// @notice ✅ NEW FUNCTION: Creates LP from USDC only (swaps half to USDT)
    function mintLpFromUsdcOnly(
        uint256 petId,
        uint256 usdcAmount,
        int24 tickLower,
        int24 tickUpper,
        address recipient
    ) external returns (uint256 positionId) {
        if (usdcAmount == 0) revert ZeroInput();
        if (recipient == address(0)) revert UnauthorizedCaller();

        tickLower = _alignTick(tickLower);
        tickUpper = _alignTick(tickUpper);

        Currency usdcCurrency = usdcUsdtPoolKey.currency0;
        IERC20(Currency.unwrap(usdcCurrency)).transferFrom(msg.sender, address(this), usdcAmount);

        MintFromUsdcOnlyParams memory params = MintFromUsdcOnlyParams({
            isSwapAndMint: false,
            isSingleToken: true, // ✅ Discriminator
            petId: petId,
            usdcAmount: usdcAmount,
            tickLower: tickLower,
            tickUpper: tickUpper,
            recipient: recipient
        });

        bytes memory result = POOL_MANAGER.unlock(abi.encode(params));
        (uint128 liquidity, uint256 returnedPositionId) = abi.decode(result, (uint128, uint256));
        positionId = returnedPositionId;

        emit LiquidityAdded(
            recipient,
            positionId,
            0,
            uint128(usdcAmount / 2),
            uint128(usdcAmount / 2),
            tickLower,
            tickUpper,
            liquidity,
            block.timestamp
        );
    }

    /// @notice ✅ MODIFIED: Updated routing logic
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(POOL_MANAGER)) revert UnauthorizedCaller();

        (bool isSwapAndMint, bool isSingleToken) = abi.decode(data, (bool, bool));

        if (isSwapAndMint) {
            SwapAndMintParams memory params = abi.decode(data, (SwapAndMintParams));
            return _handleSwapAndMint(params);
        } else if (isSingleToken) {
            MintFromUsdcOnlyParams memory params = abi.decode(data, (MintFromUsdcOnlyParams));
            return _handleMintFromUsdcOnly(params);
        } else {
            MintFromTokensParams memory params = abi.decode(data, (MintFromTokensParams));
            return _handleMintFromTokens(params);
        }
    }

    function _handleSwapAndMint(SwapAndMintParams memory params) internal returns (bytes memory) {
        BalanceDelta delta1 = POOL_MANAGER.swap(
            ethUsdcPoolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(uint256(params.ethForUsdc)),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            bytes("")
        );

        BalanceDelta delta2 = POOL_MANAGER.swap(
            ethUsdtPoolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(uint256(params.ethForUsdt)),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            bytes("")
        );

        require(delta1.amount1() > 0, "Invalid USDC swap delta");
        require(delta2.amount1() > 0, "Invalid USDT swap delta");
        
        uint128 usdcReceived = uint128(delta1.amount1());
        uint128 usdtReceived = uint128(delta2.amount1());
        
        if (usdcReceived < params.minUsdcOut) {
            revert InsufficientOutput(params.minUsdcOut, usdcReceived);
        }
        if (usdtReceived < params.minUsdtOut) {
            revert InsufficientOutput(params.minUsdtOut, usdtReceived);
        }

        (uint160 sqrtPrice,,,) = StateLibrary.getSlot0(POOL_MANAGER, usdcUsdtPoolKey.toId());
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPrice,
            TickMath.getSqrtPriceAtTick(params.tickLower),
            TickMath.getSqrtPriceAtTick(params.tickUpper),
            usdcReceived,
            usdtReceived
        );

        uint256 positionId = uint256(keccak256(abi.encodePacked(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            block.timestamp
        )));
        
        bytes32 salt = bytes32(positionId);
        
        // ✅ MODIFIED: Added petId (5 fields)
        bytes memory hookData = abi.encode(
            params.recipient,
            params.petId,
            positionId,
            params.tickLower,
            params.tickUpper
        );
        
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

        require(delta1.amount0() < 0, "Expected negative ETH delta from swap1");
        require(delta2.amount0() < 0, "Expected negative ETH delta from swap2");
        uint128 totalEthOwed = uint128(-delta1.amount0()) + uint128(-delta2.amount0());
        POOL_MANAGER.settle{value: totalEthOwed}();
        
        int128 netUsdcDelta = delta1.amount1() + delta3.amount0();
        int128 netUsdtDelta = delta2.amount1() + delta3.amount1();
        
        Currency usdcCurrency = usdcUsdtPoolKey.currency0;
        Currency usdtCurrency = usdcUsdtPoolKey.currency1;
        
        if (netUsdcDelta < 0) {
            POOL_MANAGER.take(usdcCurrency, address(this), usdcReceived);
            POOL_MANAGER.sync(usdcCurrency);
            IERC20(Currency.unwrap(usdcCurrency)).transfer(address(POOL_MANAGER), uint128(-netUsdcDelta));
            POOL_MANAGER.settle();
        } else if (netUsdcDelta > 0) {
            POOL_MANAGER.take(usdcCurrency, params.recipient, uint128(netUsdcDelta));
        }
        
        if (netUsdtDelta < 0) {
            POOL_MANAGER.take(usdtCurrency, address(this), usdtReceived);
            POOL_MANAGER.sync(usdtCurrency);
            IERC20(Currency.unwrap(usdtCurrency)).transfer(address(POOL_MANAGER), uint128(-netUsdtDelta));
            POOL_MANAGER.settle();
        } else if (netUsdtDelta > 0) {
            POOL_MANAGER.take(usdtCurrency, params.recipient, uint128(netUsdtDelta));
        }

        return abi.encode(liquidity, positionId);
    }

    function _handleMintFromTokens(MintFromTokensParams memory params) internal returns (bytes memory) {
        Currency usdcCurrency = usdcUsdtPoolKey.currency0;
        Currency usdtCurrency = usdcUsdtPoolKey.currency1;

        (uint160 sqrtPrice,,,) = StateLibrary.getSlot0(POOL_MANAGER, usdcUsdtPoolKey.toId());
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPrice,
            TickMath.getSqrtPriceAtTick(params.tickLower),
            TickMath.getSqrtPriceAtTick(params.tickUpper),
            params.usdcAmount,
            params.usdtAmount
        );

        uint256 positionId = uint256(keccak256(abi.encodePacked(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            block.timestamp
        )));
        
        bytes32 salt = bytes32(positionId);
        
        // ✅ MODIFIED: Added petId (5 fields)
        bytes memory hookData = abi.encode(
            params.recipient,
            params.petId,
            positionId,
            params.tickLower,
            params.tickUpper
        );
        
        (BalanceDelta delta,) = POOL_MANAGER.modifyLiquidity(
            usdcUsdtPoolKey,
            ModifyLiquidityParams({
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: salt
            }),
            hookData
        );

        require(delta.amount0() < 0, "Expected negative USDC delta");
        require(delta.amount1() < 0, "Expected negative USDT delta");
        
        uint128 usdcOwed = uint128(-delta.amount0());
        uint128 usdtOwed = uint128(-delta.amount1());

        POOL_MANAGER.sync(usdcCurrency);
        IERC20(Currency.unwrap(usdcCurrency)).transfer(address(POOL_MANAGER), usdcOwed);
        POOL_MANAGER.settle();

        POOL_MANAGER.sync(usdtCurrency);
        IERC20(Currency.unwrap(usdtCurrency)).transfer(address(POOL_MANAGER), usdtOwed);
        POOL_MANAGER.settle();

        uint128 usdcLeftover = params.usdcAmount - usdcOwed;
        uint128 usdtLeftover = params.usdtAmount - usdtOwed;
        
        if (usdcLeftover > 0) {
            POOL_MANAGER.take(usdcCurrency, params.recipient, usdcLeftover);
        }
        if (usdtLeftover > 0) {
            POOL_MANAGER.take(usdtCurrency, params.recipient, usdtLeftover);
        }

        return abi.encode(liquidity, positionId);
    }

    /// @dev ✅ NEW FUNCTION: Handle mint LP from USDC only
    function _handleMintFromUsdcOnly(MintFromUsdcOnlyParams memory params) internal returns (bytes memory) {
        Currency usdcCurrency = usdcUsdtPoolKey.currency0;
        Currency usdtCurrency = usdcUsdtPoolKey.currency1;

        uint128 halfUsdc = uint128(params.usdcAmount / 2);
        uint128 remainingUsdc = uint128(params.usdcAmount) - halfUsdc;

        BalanceDelta swapDelta = POOL_MANAGER.swap(
            usdcUsdtPoolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(uint256(halfUsdc)),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            bytes("")
        );

        require(swapDelta.amount1() > 0, "Invalid USDT swap delta");
        uint128 usdtReceived = uint128(swapDelta.amount1());

        require(swapDelta.amount0() < 0, "Expected negative USDC delta");
        uint128 usdcOwed = uint128(-swapDelta.amount0());
        
        POOL_MANAGER.sync(usdcCurrency);
        IERC20(Currency.unwrap(usdcCurrency)).transfer(address(POOL_MANAGER), usdcOwed);
        POOL_MANAGER.settle();
        
        POOL_MANAGER.take(usdtCurrency, address(this), usdtReceived);

        (uint160 sqrtPrice,,,) = StateLibrary.getSlot0(POOL_MANAGER, usdcUsdtPoolKey.toId());
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPrice,
            TickMath.getSqrtPriceAtTick(params.tickLower),
            TickMath.getSqrtPriceAtTick(params.tickUpper),
            remainingUsdc,
            usdtReceived
        );

        uint256 positionId = uint256(keccak256(abi.encodePacked(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            block.timestamp
        )));
        
        bytes32 salt = bytes32(positionId);
        
        // ✅ Added petId (5 fields)
        bytes memory hookData = abi.encode(
            params.recipient,
            params.petId,
            positionId,
            params.tickLower,
            params.tickUpper
        );
        
        (BalanceDelta lpDelta,) = POOL_MANAGER.modifyLiquidity(
            usdcUsdtPoolKey,
            ModifyLiquidityParams({
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: salt
            }),
            hookData
        );

        require(lpDelta.amount0() < 0, "Expected negative USDC delta");
        require(lpDelta.amount1() < 0, "Expected negative USDT delta");
        
        uint128 usdcNeeded = uint128(-lpDelta.amount0());
        uint128 usdtNeeded = uint128(-lpDelta.amount1());

        POOL_MANAGER.sync(usdcCurrency);
        IERC20(Currency.unwrap(usdcCurrency)).transfer(address(POOL_MANAGER), usdcNeeded);
        POOL_MANAGER.settle();

        POOL_MANAGER.sync(usdtCurrency);
        IERC20(Currency.unwrap(usdtCurrency)).transfer(address(POOL_MANAGER), usdtNeeded);
        POOL_MANAGER.settle();

        uint128 usdcLeftover = remainingUsdc > usdcNeeded ? remainingUsdc - usdcNeeded : 0;
        uint128 usdtLeftover = usdtReceived > usdtNeeded ? usdtReceived - usdtNeeded : 0;
        
        if (usdcLeftover > 0) {
            POOL_MANAGER.take(usdcCurrency, params.recipient, usdcLeftover);
        }
        if (usdtLeftover > 0) {
            POOL_MANAGER.take(usdtCurrency, params.recipient, usdtLeftover);
        }

        return abi.encode(liquidity, positionId);
    }

    function travelToChain(
        uint256 petId,
        uint256 destinationChainId,
        int24 tickLower,
        int24 tickUpper
    ) external returns (bytes32 compactId) {
        require(petRegistry != address(0), "Registry not set");
        
        (address owner, , , , uint256 chainId, , uint256 positionId) = 
            PetRegistry(petRegistry).pets(petId);
        
        require(owner == msg.sender, "Not pet owner");
        require(chainId == block.chainid, "Pet not on this chain");
        require(positionId != 0, "No active position");
        
        Currency usdcCurrency = usdcUsdtPoolKey.currency0;
        Currency usdtCurrency = usdcUsdtPoolKey.currency1;
        
        uint128 usdcAmount = 1000e6;
        uint128 usdtAmount = 1000e6;
        
        IERC20(Currency.unwrap(usdcCurrency)).transferFrom(msg.sender, address(this), usdcAmount);
        IERC20(Currency.unwrap(usdtCurrency)).transferFrom(msg.sender, address(this), usdtAmount);
        
        compactId = keccak256(abi.encodePacked(
            msg.sender,
            petId,
            block.chainid,
            destinationChainId,
            usdcAmount,
            usdtAmount,
            tickLower,
            tickUpper,
            block.timestamp
        ));
        
        emit IntentCreated(
            compactId,
            petId,
            msg.sender,
            block.chainid,
            destinationChainId,
            usdcAmount,
            usdtAmount,
            tickLower,
            tickUpper,
            block.timestamp
        );
        
        return compactId;
    }

    function quoteSwapOutputs(uint256 ethAmount) 
        external 
        view 
        returns (uint128 usdcOut, uint128 usdtOut) 
    {
        if (ethAmount == 0) return (0, 0);
        
        uint128 half = uint128(ethAmount / 2);
        uint128 remainder = uint128(ethAmount) - half;
        
        usdcOut = _quoteExactInputSingle(ethUsdcPoolKey, true, half);
        usdtOut = _quoteExactInputSingle(ethUsdtPoolKey, true, remainder);
    }

    function _quoteExactInputSingle(
        PoolKey memory poolKey,
        bool zeroForOne,
        uint128 amountIn
    ) internal view returns (uint128 amountOut) {
        (, int24 tick,,) = StateLibrary.getSlot0(POOL_MANAGER, poolKey.toId());
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        
        if (zeroForOne) {
            uint256 amount1 = FullMath.mulDiv(amountIn, sqrtPriceX96, FixedPoint96.Q96);
            amount1 = FullMath.mulDiv(amount1, sqrtPriceX96, FixedPoint96.Q96);
            amount1 = (amount1 * 9950) / 10000;
            amountOut = uint128(amount1);
        } else {
            uint256 amount0 = FullMath.mulDiv(amountIn, FixedPoint96.Q96, sqrtPriceX96);
            amount0 = FullMath.mulDiv(amount0, FixedPoint96.Q96, sqrtPriceX96);
            amount0 = (amount0 * 9950) / 10000;
            amountOut = uint128(amount0);
        }
    }

    function _alignTick(int24 tick) internal view returns (int24 aligned) {
        int24 spacing = TICK_SPACING;
        int24 compressed = tick / spacing;
        aligned = compressed * spacing;
    }
}
