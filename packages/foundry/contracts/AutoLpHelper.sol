// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
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

    error InvalidMsgValue(uint256 sent, uint256 expected);
    error ZeroInput();
    error UnsupportedPayer(address payer);

    PoolKey public ethUsdcPoolKey;
    PoolKey public ethUsdtPoolKey;
    PoolKey public usdcUsdtPoolKey;

    int24 public immutable tickSpacing;
    int24 public immutable tickLowerOffset;
    int24 public immutable tickUpperOffset;

    constructor(
        IPoolManager _poolManager,
        PoolKey memory _ethUsdcPoolKey,
        PoolKey memory _ethUsdtPoolKey,
        PoolKey memory _usdcUsdtPoolKey,
        int24 _tickSpacing,
        int24 _tickLowerOffset,
        int24 _tickUpperOffset
    ) V4Router(_poolManager) {
        ethUsdcPoolKey = _ethUsdcPoolKey;
        ethUsdtPoolKey = _ethUsdtPoolKey;
        usdcUsdtPoolKey = _usdcUsdtPoolKey;
        tickSpacing = _tickSpacing;
        tickLowerOffset = _tickLowerOffset;
        tickUpperOffset = _tickUpperOffset;
    }

    function msgSender() public view override returns (address) {
        return address(this);
    }

    function swapEthToUsdcUsdtAndMint(uint128 minUsdcOut, uint128 minUsdtOut)
        external
        payable
        returns (int24 tickLower, int24 tickUpper, uint256 positionId)
    {
        if (msg.value == 0) revert ZeroInput();

        uint128 half = uint128(msg.value / 2);
        uint128 remainder = uint128(msg.value) - half;

        _swapExactInSingleToSelf(ethUsdcPoolKey, CurrencyLibrary.ADDRESS_ZERO, half, minUsdcOut);
        _swapExactInSingleToSelf(ethUsdtPoolKey, CurrencyLibrary.ADDRESS_ZERO, remainder, minUsdtOut);

        (uint160 sqrtPriceX96, int24 tickCurrent,,) = StateLibrary.getSlot0(poolManager, usdcUsdtPoolKey.toId());

        tickLower = _alignTick(tickCurrent + tickLowerOffset);
        tickUpper = _alignTick(tickCurrent + tickUpperOffset);

        uint256 amount0 = usdcUsdtPoolKey.currency0.balanceOfSelf();
        uint256 amount1 = usdcUsdtPoolKey.currency1.balanceOfSelf();

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );

        positionId = uint256(keccak256(abi.encode(msg.sender, tickLower, tickUpper, block.number)));
        bytes memory hookData = abi.encode(msg.sender, positionId);

        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            usdcUsdtPoolKey,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: bytes32(positionId)
            }),
            hookData
        );

        _settleDelta(usdcUsdtPoolKey.currency0, delta.amount0());
        _settleDelta(usdcUsdtPoolKey.currency1, delta.amount1());

        _sweepIfAny(usdcUsdtPoolKey.currency0, msg.sender);
        _sweepIfAny(usdcUsdtPoolKey.currency1, msg.sender);
        _refundEth();
    }

    function _swapExactInSingleToSelf(
        PoolKey memory poolKey,
        Currency inputCurrency,
        uint128 amountIn,
        uint128 minAmountOut
    ) internal {
        bool zeroForOne = poolKey.currency0 == inputCurrency;
        IV4Router.ExactInputSingleParams memory params =
            IV4Router.ExactInputSingleParams(poolKey, zeroForOne, amountIn, minAmountOut, bytes(""));

        bytes[] memory paramsArr = new bytes[](3);
        bytes memory actions = new bytes(3);
        actions[0] = bytes1(uint8(Actions.SWAP_EXACT_IN_SINGLE));
        actions[1] = bytes1(uint8(Actions.SETTLE));
        actions[2] = bytes1(uint8(Actions.TAKE));

        Currency outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        paramsArr[0] = abi.encode(params);
        paramsArr[1] = abi.encode(inputCurrency, ActionConstants.OPEN_DELTA, false);
        paramsArr[2] = abi.encode(outputCurrency, ActionConstants.ADDRESS_THIS, ActionConstants.OPEN_DELTA);

        this.executeActionsWrapper(abi.encode(actions, paramsArr));
    }

    function executeActionsWrapper(bytes calldata data) external {
        require(msg.sender == address(this), "Only self");
        _executeActions(data);
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

    function _refundEth() internal {
        if (address(this).balance > 0) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "ETH refund failed");
        }
    }

    function _pay(Currency currency, address payer, uint256 amount) internal override {
        if (payer != address(this)) revert UnsupportedPayer(payer);
        currency.transfer(address(poolManager), amount);
    }
}
