// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {V4Router} from "@uniswap/v4-periphery/src/V4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {ActionConstants} from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

contract AutoLpHelper is V4Router {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    error ZeroInput();
    error UnsupportedPayer(address payer);
    error ActionNotSupported(uint256 action);
    error InProgress();
    error NotInProgress();

    PoolKey public ethUsdcPoolKey;
    PoolKey public ethUsdtPoolKey;
    PoolKey public usdcUsdtPoolKey;

    address public immutable weth;

    int24 public immutable tickSpacing;
    int24 public immutable tickLowerOffset;
    int24 public immutable tickUpperOffset;

    address private currentOwner;

    int24 private lastTickLower;
    int24 private lastTickUpper;
    uint256 private lastPositionId;

    uint256 private constant ACTION_MINT_LP = 0x80;
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 200;

    constructor(
        IPoolManager _poolManager,
        PoolKey memory _ethUsdcPoolKey,
        PoolKey memory _ethUsdtPoolKey,
        PoolKey memory _usdcUsdtPoolKey,
        address _weth,
        int24 _tickSpacing,
        int24 _tickLowerOffset,
        int24 _tickUpperOffset
    ) V4Router(_poolManager) {
        ethUsdcPoolKey = _ethUsdcPoolKey;
        ethUsdtPoolKey = _ethUsdtPoolKey;
        usdcUsdtPoolKey = _usdcUsdtPoolKey;
        weth = _weth;
        tickSpacing = _tickSpacing;
        tickLowerOffset = _tickLowerOffset;
        tickUpperOffset = _tickUpperOffset;
    }

    function msgSender() public view override returns (address) {
        return address(this);
    }

    receive() external payable {}

    function swapEthToUsdcUsdtAndMint()
        external
        payable
        returns (int24 tickLower, int24 tickUpper, uint256 positionId)
    {
        if (msg.value == 0) revert ZeroInput();
        if (currentOwner != address(0)) revert InProgress();
        currentOwner = msg.sender;

        _wrapEth(msg.value);

        uint128 half = uint128(msg.value / 2);
        uint128 remainder = uint128(msg.value) - half;

        (uint160 sqrtPriceEthUsdc,,,) = StateLibrary.getSlot0(poolManager, ethUsdcPoolKey.toId());
        (uint160 sqrtPriceEthUsdt,,,) = StateLibrary.getSlot0(poolManager, ethUsdtPoolKey.toId());

        uint128 minUsdcOut = _applySlippage(_spotQuote(half, sqrtPriceEthUsdc, ethUsdcPoolKey.currency0 == Currency.wrap(weth)));
        uint128 minUsdtOut = _applySlippage(_spotQuote(remainder, sqrtPriceEthUsdt, ethUsdtPoolKey.currency0 == Currency.wrap(weth)));

        (tickLower, tickUpper, positionId) = _executeSwapAndMint(half, remainder, minUsdcOut, minUsdtOut);

        currentOwner = address(0);
    }

    function _executeSwapAndMint(
        uint128 amountWethForUsdc,
        uint128 amountWethForUsdt,
        uint128 minUsdcOut,
        uint128 minUsdtOut
    ) internal returns (int24 tickLower, int24 tickUpper, uint256 positionId) {
        bytes memory actions = new bytes(6);
        bytes[] memory params = new bytes[](6);

        Currency wethCurrency = Currency.wrap(weth);

        actions[0] = bytes1(uint8(Actions.SWAP_EXACT_IN_SINGLE));
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams(ethUsdcPoolKey, ethUsdcPoolKey.currency0 == wethCurrency, amountWethForUsdc, minUsdcOut, bytes(""))
        );

        actions[1] = bytes1(uint8(Actions.SETTLE));
        params[1] = abi.encode(wethCurrency, ActionConstants.OPEN_DELTA, false);

        actions[2] = bytes1(uint8(Actions.TAKE));
        params[2] = abi.encode(ethUsdcPoolKey.currency0 == wethCurrency ? ethUsdcPoolKey.currency1 : ethUsdcPoolKey.currency0, ActionConstants.ADDRESS_THIS, ActionConstants.OPEN_DELTA);

        actions[3] = bytes1(uint8(Actions.SWAP_EXACT_IN_SINGLE));
        params[3] = abi.encode(
            IV4Router.ExactInputSingleParams(ethUsdtPoolKey, ethUsdtPoolKey.currency0 == wethCurrency, amountWethForUsdt, minUsdtOut, bytes(""))
        );

        actions[4] = bytes1(uint8(Actions.SETTLE));
        params[4] = abi.encode(wethCurrency, ActionConstants.OPEN_DELTA, false);

        actions[5] = bytes1(uint8(Actions.TAKE));
        params[5] = abi.encode(ethUsdtPoolKey.currency0 == wethCurrency ? ethUsdtPoolKey.currency1 : ethUsdtPoolKey.currency0, ActionConstants.ADDRESS_THIS, ActionConstants.OPEN_DELTA);

        _executeActions(abi.encode(actions, params));

        bytes memory mintActions = new bytes(1);
        bytes[] memory mintParams = new bytes[](1);
        mintActions[0] = bytes1(uint8(ACTION_MINT_LP));
        mintParams[0] = abi.encode(usdcUsdtPoolKey);

        _executeActions(abi.encode(mintActions, mintParams));

        tickLower = lastTickLower;
        tickUpper = lastTickUpper;
        positionId = lastPositionId;
    }

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

    function _applySlippage(uint128 amountOut) internal pure returns (uint128) {
        uint256 adjusted = (uint256(amountOut) * (10_000 - DEFAULT_SLIPPAGE_BPS)) / 10_000;
        return uint128(adjusted);
    }

    function _handleAction(uint256 action, bytes calldata params) internal override {
        if (action == ACTION_MINT_LP) {
            PoolKey memory poolKey = abi.decode(params, (PoolKey));
            _mintWithBalances(poolKey);
            return;
        }

        super._handleAction(action, params);
    }

    function _mintWithBalances(PoolKey memory poolKey) internal {
        if (currentOwner == address(0)) revert NotInProgress();
        (uint160 sqrtPriceX96, int24 tickCurrent,,) = StateLibrary.getSlot0(poolManager, poolKey.toId());

        int24 tickLower = _alignTick(tickCurrent + tickLowerOffset);
        int24 tickUpper = _alignTick(tickCurrent + tickUpperOffset);

        uint256 amount0 = poolKey.currency0.balanceOfSelf();
        uint256 amount1 = poolKey.currency1.balanceOfSelf();

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );

        uint256 positionId = uint256(keccak256(abi.encode(currentOwner, tickLower, tickUpper, block.number)));
        bytes memory hookData = abi.encode(currentOwner, positionId, tickLower, tickUpper);

        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: bytes32(positionId)
            }),
            hookData
        );

        _settleDelta(poolKey.currency0, delta.amount0());
        _settleDelta(poolKey.currency1, delta.amount1());

        _sweepIfAny(poolKey.currency0, currentOwner);
        _sweepIfAny(poolKey.currency1, currentOwner);

        lastTickLower = tickLower;
        lastTickUpper = tickUpper;
        lastPositionId = positionId;
    }

    function _alignTick(int24 tick) internal view returns (int24 aligned) {
        int24 spacing = tickSpacing;
        int24 compressed = tick / spacing;
        aligned = compressed * spacing;
    }

    function _settleDelta(Currency currency, int128 delta) internal {
        if (delta < 0) {
            _settle(currency, address(this), uint256(uint128(-delta)));
        } else if (delta > 0) {
            _take(currency, address(this), uint256(uint128(delta)));
        }
    }

    function _sweepIfAny(Currency currency, address to) internal {
        uint256 balance = currency.balanceOfSelf();
        if (balance > 0) currency.transfer(to, balance);
    }

    function _wrapEth(uint256 amount) internal {
        (bool success,) = weth.call{value: amount}(abi.encodeWithSignature("deposit()"));
        require(success, "WETH deposit failed");
    }

    function _pay(Currency currency, address payer, uint256 amount) internal override {
        if (payer != address(this)) revert UnsupportedPayer(payer);
        currency.transfer(address(poolManager), amount);
    }
}
