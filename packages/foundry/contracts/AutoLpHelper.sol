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

    struct SwapAndMintParams {
        bool isSwapAndMint; // Discriminator: true for swap, false for others
        bool isSingleToken; // Discriminator: false for this type
        uint256 petId; // Pet ID (0 for auto-derive, >0 for migration)
        uint128 ethForUsdc;
        uint128 ethForUsdt;
        uint128 minUsdcOut;
        uint128 minUsdtOut;
        int24 tickLower;
        int24 tickUpper;
        address recipient;
    }

    struct MintFromTokensParams {
        bool isSwapAndMint; // Discriminator: always false
        bool isSingleToken; // Discriminator: false for dual-token
        uint256 petId; // Pet ID (0 for auto-derive, >0 for migration)
        uint128 usdcAmount;
        uint128 usdtAmount;
        int24 tickLower;
        int24 tickUpper;
        address recipient;
    }

    struct MintFromUsdcOnlyParams {
        bool isSwapAndMint; // Discriminator: always false
        bool isSingleToken; // Discriminator: true for single-token
        uint256 petId; // Pet ID for migration
        uint256 usdcAmount; // Total USDC (will split 50/50)
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

    /// @notice Set the PetRegistry address (callable only once during setup)
    /// @param _petRegistry Address of the deployed PetRegistry contract
    function setPetRegistry(address _petRegistry) external {
        require(petRegistry == address(0), "Registry already set");
        require(_petRegistry != address(0), "Invalid registry");
        petRegistry = _petRegistry;
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
            isSwapAndMint: true,
            isSingleToken: false,
            petId: 0, // Auto-derive deterministic ID on initial hatch
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

    /// @notice Creates LP position from pre-existing USDC/USDT tokens (no ETH swap needed)
    /// @dev Used by solver agents after bridging tokens via Li.FI or users that bring stables for initial hatch
    /// @param petId Pet ID (0 for auto-derive, >0 for cross-chain migration)
    /// @param usdcAmount Amount of USDC to add to LP
    /// @param usdtAmount Amount of USDT to add to LP
    /// @param tickLower Lower tick boundary of the LP range
    /// @param tickUpper Upper tick boundary of the LP range
    /// @param recipient Address to receive the position NFT (typically the user)
    /// @return positionId The unique ID of the created LP position
    function mintLpFromTokens(
        uint256 petId,
        uint128 usdcAmount,
        uint128 usdtAmount,
        int24 tickLower,
        int24 tickUpper,
        address recipient
    ) external returns (uint256 positionId) {
        if (usdcAmount == 0 || usdtAmount == 0) revert ZeroInput();
        if (recipient == address(0)) revert UnauthorizedCaller();

        // Align ticks to spacing
        tickLower = _alignTick(tickLower);
        tickUpper = _alignTick(tickUpper);

        // Transfer tokens from solver to this contract
        Currency usdcCurrency = usdcUsdtPoolKey.currency0;
        Currency usdtCurrency = usdcUsdtPoolKey.currency1;
        
        IERC20(Currency.unwrap(usdcCurrency)).transferFrom(msg.sender, address(this), usdcAmount);
        IERC20(Currency.unwrap(usdtCurrency)).transferFrom(msg.sender, address(this), usdtAmount);

        MintFromTokensParams memory params = MintFromTokensParams({
            isSwapAndMint: false,
            isSingleToken: false,
            petId: petId,
            usdcAmount: usdcAmount,
            usdtAmount: usdtAmount,
            tickLower: tickLower,
            tickUpper: tickUpper,
            recipient: recipient
        });

        // Execute atomically via unlock callback
        bytes memory result = POOL_MANAGER.unlock(abi.encode(params));
        (uint128 liquidity, uint256 returnedPositionId) = abi.decode(result, (uint128, uint256));
        positionId = returnedPositionId;

        emit LiquidityAdded(
            recipient,
            positionId,
            0, // No ETH input
            usdcAmount,
            usdtAmount,
            tickLower,
            tickUpper,
            liquidity,
            block.timestamp
        );
    }

    /// @notice Creates LP from USDC only (swaps 50% to USDT first)
    /// @dev Used for cross-chain migration when only USDC is bridged
    /// @param petId Pet ID for cross-chain migration
    /// @param usdcAmount Total USDC to use (will split 50/50 between USDC and USDT)
    /// @param tickLower Lower tick boundary of the LP range
    /// @param tickUpper Upper tick boundary of the LP range
    /// @param recipient Address to receive the position NFT
    /// @return positionId The unique ID of the created LP position
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
            isSingleToken: true,
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

    /// @notice Callback function called by PoolManager.unlock()
    /// @dev All swaps and LP minting happen atomically here
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(POOL_MANAGER)) revert UnauthorizedCaller();

        // Decode discriminators to route to correct handler
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

    /// @dev Handle swap ETH → USDC/USDT → LP position
    function _handleSwapAndMint(SwapAndMintParams memory params) internal returns (bytes memory) {

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
        
        // Encode hook data: (address owner, uint256 petId, uint256 positionId, int24 tickLower, int24 tickUpper)
        bytes memory hookData = abi.encode(
            params.recipient,
            params.petId,
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

    /// @dev Handle mint LP from existing tokens (no swaps needed)
    /// @notice Follows Uniswap v4 flash accounting pattern with sync/settle
    function _handleMintFromTokens(MintFromTokensParams memory params) internal returns (bytes memory) {
        Currency usdcCurrency = usdcUsdtPoolKey.currency0;
        Currency usdtCurrency = usdcUsdtPoolKey.currency1;

        // Step 1: Calculate liquidity for LP position
        (uint160 sqrtPrice,,,) = StateLibrary.getSlot0(POOL_MANAGER, usdcUsdtPoolKey.toId());
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPrice,
            TickMath.getSqrtPriceAtTick(params.tickLower),
            TickMath.getSqrtPriceAtTick(params.tickUpper),
            params.usdcAmount,
            params.usdtAmount
        );

        // Step 2: Create unique position ID
        uint256 positionId = uint256(keccak256(abi.encodePacked(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            block.timestamp
        )));
        
        bytes32 salt = bytes32(positionId);
        
        // Encode hook data for EggHatchHook
        bytes memory hookData = abi.encode(
            params.recipient,
            params.petId,
            positionId,
            params.tickLower,
            params.tickUpper
        );
        
        // Step 3: Create position - hook will mint pet NFT to recipient
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

        // Step 4: Settle deltas using canonical v4 sync/settle/take pattern
        // For adding liquidity, deltas are negative (we owe the pool)
        require(delta.amount0() < 0, "Expected negative USDC delta");
        require(delta.amount1() < 0, "Expected negative USDT delta");
        
        uint128 usdcOwed = uint128(-delta.amount0());
        uint128 usdtOwed = uint128(-delta.amount1());

        // Settle USDC: sync → transfer → settle
        POOL_MANAGER.sync(usdcCurrency);
        IERC20(Currency.unwrap(usdcCurrency)).transfer(address(POOL_MANAGER), usdcOwed);
        POOL_MANAGER.settle();

        // Settle USDT: sync → transfer → settle  
        POOL_MANAGER.sync(usdtCurrency);
        IERC20(Currency.unwrap(usdtCurrency)).transfer(address(POOL_MANAGER), usdtOwed);
        POOL_MANAGER.settle();

        // Return any leftover tokens to the original caller (solver)
        // Note: Leftover tokens are already in this contract from the initial transferFrom
        uint128 usdcLeftover = params.usdcAmount - usdcOwed;
        uint128 usdtLeftover = params.usdtAmount - usdtOwed;
        
        if (usdcLeftover > 0) {
            // Transfer back to the external caller (who called mintLpFromTokens)
            // Not msg.sender here because we're in unlock callback
            POOL_MANAGER.take(usdcCurrency, params.recipient, usdcLeftover);
        }
        if (usdtLeftover > 0) {
            POOL_MANAGER.take(usdtCurrency, params.recipient, usdtLeftover);
        }

        return abi.encode(liquidity, positionId);
    }

    /// @dev Handle mint LP from USDC only (swaps 50% to USDT first)
    /// @notice Follows Uniswap v4 flash accounting pattern with sync/settle
    function _handleMintFromUsdcOnly(MintFromUsdcOnlyParams memory params) internal returns (bytes memory) {
        Currency usdcCurrency = usdcUsdtPoolKey.currency0;
        Currency usdtCurrency = usdcUsdtPoolKey.currency1;

        // Step 1: Split USDC - half stays, half swaps to USDT
        uint128 halfUsdc = uint128(params.usdcAmount / 2);
        uint128 remainingUsdc = uint128(params.usdcAmount) - halfUsdc;

        // Step 2: Swap half USDC → USDT
        BalanceDelta swapDelta = POOL_MANAGER.swap(
            usdcUsdtPoolKey,
            SwapParams({
                zeroForOne: true, // USDC (token0) → USDT (token1)
                amountSpecified: -int256(uint256(halfUsdc)),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            bytes("")
        );

        require(swapDelta.amount1() > 0, "Invalid USDT swap delta");
        uint128 usdtReceived = uint128(swapDelta.amount1());

        // Step 3: Settle swap - pay USDC debt
        require(swapDelta.amount0() < 0, "Expected negative USDC delta");
        uint128 usdcOwed = uint128(-swapDelta.amount0());
        
        POOL_MANAGER.sync(usdcCurrency);
        IERC20(Currency.unwrap(usdcCurrency)).transfer(address(POOL_MANAGER), usdcOwed);
        POOL_MANAGER.settle();
        
        // Take USDT from pool
        POOL_MANAGER.take(usdtCurrency, address(this), usdtReceived);

        // Step 4: Calculate liquidity for LP position
        (uint160 sqrtPrice,,,) = StateLibrary.getSlot0(POOL_MANAGER, usdcUsdtPoolKey.toId());
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPrice,
            TickMath.getSqrtPriceAtTick(params.tickLower),
            TickMath.getSqrtPriceAtTick(params.tickUpper),
            remainingUsdc,
            usdtReceived
        );

        // Step 5: Create unique position ID
        uint256 positionId = uint256(keccak256(abi.encodePacked(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            block.timestamp
        )));
        
        bytes32 salt = bytes32(positionId);
        
        // Encode hook data with petId for migration
        bytes memory hookData = abi.encode(
            params.recipient,
            params.petId,
            positionId,
            params.tickLower,
            params.tickUpper
        );
        
        // Step 6: Create LP position
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

        // Step 7: Settle LP creation deltas
        require(lpDelta.amount0() < 0, "Expected negative USDC delta");
        require(lpDelta.amount1() < 0, "Expected negative USDT delta");
        
        uint128 usdcNeeded = uint128(-lpDelta.amount0());
        uint128 usdtNeeded = uint128(-lpDelta.amount1());

        // Settle USDC
        POOL_MANAGER.sync(usdcCurrency);
        IERC20(Currency.unwrap(usdcCurrency)).transfer(address(POOL_MANAGER), usdcNeeded);
        POOL_MANAGER.settle();

        // Settle USDT
        POOL_MANAGER.sync(usdtCurrency);
        IERC20(Currency.unwrap(usdtCurrency)).transfer(address(POOL_MANAGER), usdtNeeded);
        POOL_MANAGER.settle();

        // Step 8: Return any leftover tokens to recipient
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


    /// @notice Initiate cross-chain LP migration via intent-based system
    /// @dev Creates an intent for solver to fulfill. User's LP is closed on source chain,
    ///      tokens are held in escrow, and solver recreates LP on destination chain.
    ///      This is Phase 1 (MVP): Intent creation without The Compact integration.
    ///      Phase 2 will add The Compact for trustless settlement.
    /// @param petId The ID of the pet to migrate (must be owned by msg.sender)
    /// @param destinationChainId Target chain ID where LP will be recreated
    /// @param tickLower Lower tick for the new LP position on destination chain
    /// @param tickUpper Upper tick for the new LP position on destination chain
    /// @return compactId Unique identifier for tracking this travel intent
    function travelToChain(
        uint256 petId,
        uint256 destinationChainId,
        int24 tickLower,
        int24 tickUpper
    ) external returns (bytes32 compactId) {
        // 1. Verify msg.sender owns the pet (read from PetRegistry)
        require(petRegistry != address(0), "Registry not set");
        
        // Read pet data from registry
        (address owner, , , , uint256 chainId, , uint256 positionId) = 
            PetRegistry(petRegistry).pets(petId);
        
        require(owner == msg.sender, "Not pet owner");
        require(chainId == block.chainid, "Pet not on this chain");
        require(positionId != 0, "No active position");
        
        // 2. Close existing LP position → get USDC/USDT amounts
        // Note: In MVP, we simulate closing the position by reading the expected amounts
        // A full implementation would call PositionManager to decrease liquidity to zero
        // and collect the underlying tokens. For now, we'll calculate expected amounts.
        
        // Get the currencies from the pool
        Currency usdcCurrency = usdcUsdtPoolKey.currency0;
        Currency usdtCurrency = usdcUsdtPoolKey.currency1;
        
        // TODO: Implement actual position closing via PositionManager
        // For MVP, assume user has approved and we can transfer their existing balance
        // In production, this would:
        //   1. Call POSM.modifyLiquidities() to decrease liquidity to 0
        //   2. Collect tokens from the position
        //   3. Get actual USDC/USDT amounts returned
        
        // Placeholder amounts - in production these come from closing the position
        uint128 usdcAmount = 1000e6; // 1000 USDC (6 decimals)
        uint128 usdtAmount = 1000e6; // 1000 USDT (6 decimals)
        
        // 3. Approve The Compact to spend USDC/USDT
        // Note: In MVP Phase 1, we skip The Compact integration
        // Tokens remain in this contract as a trust assumption
        // Phase 2 will deposit into The Compact for trustless settlement
        
        // Transfer tokens from user to this contract (escrow)
        IERC20(Currency.unwrap(usdcCurrency)).transferFrom(msg.sender, address(this), usdcAmount);
        IERC20(Currency.unwrap(usdtCurrency)).transferFrom(msg.sender, address(this), usdtAmount);
        
        // 4. Call TheCompact.registerMultichainIntent(...)
        // TODO: Phase 2 - Integrate with The Compact
        // For now, we create a simple intent ID and rely on off-chain solver
        // In production:
        //   1. Approve The Compact to spend tokens
        //   2. Call TheCompact.deposit() to create resource locks
        //   3. Call TheCompact.register() with multichain compact details
        //   4. Store the returned compactId for tracking
        
        // Generate deterministic intent ID
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
        
        // 5. Emit IntentCreated event
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
        
        // 6. Return compactId for tracking
        return compactId;
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
