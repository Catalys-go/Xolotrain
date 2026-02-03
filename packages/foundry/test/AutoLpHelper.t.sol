// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {AutoLpHelper} from "../contracts/AutoLpHelper.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract TestAutoLp is Test {
    AutoLpHelper public autoLpHelper;
    address constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address user = address(0x123);

    function setUp() public {
        // Read pool keys from JSON
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/addresses/poolKeys.json"));
        string memory prefix = ".31337";

        PoolKey memory ethUsdc = _readPoolKey(json, string.concat(prefix, ".ETH_USDC"));
        PoolKey memory ethUsdt = _readPoolKey(json, string.concat(prefix, ".ETH_USDT"));
        PoolKey memory usdcUsdt = _readPoolKey(json, string.concat(prefix, ".USDC_USDT"));

        autoLpHelper = new AutoLpHelper(
            IPoolManager(POOL_MANAGER),
            IPositionManager(POSITION_MANAGER),
            ethUsdc,
            ethUsdt,
            usdcUsdt,
            usdcUsdt.tickSpacing,
            -6,
            6
        );

        vm.deal(user, 100 ether);
    }

    function testSwapEthToUsdcUsdtAndMint() public {
        vm.startPrank(user);

        uint256 ethAmountIn = 0.1 ether;
        console.log("User ETH balance before:", user.balance);
        console.log("Calling swapEthToUsdcUsdtAndMint with", ethAmountIn);

        uint128 liquidity = autoLpHelper.swapEthToUsdcUsdtAndMint{value: ethAmountIn}();
        
        console.log("Success!");
        console.log("Liquidity created:", liquidity);
        
        // Check that liquidity was created
        assertGt(liquidity, 0, "Liquidity should be greater than 0");
        
        // Check that some ETH was spent
        assertLt(user.balance, 100 ether, "ETH should have been spent");
        console.log("User ETH balance after:", user.balance);
        
        // Check for leftover tokens (should be minimal dust)
        uint256 usdcBalance = IERC20(USDC).balanceOf(user);
        uint256 usdtBalance = IERC20(USDT).balanceOf(user);
        console.log("User leftover USDC:", usdcBalance);
        console.log("User leftover USDT:", usdtBalance);

        vm.stopPrank();
    }

    function testSwapEthToUsdcUsdtAndMint_ZeroInput() public {
        vm.startPrank(user);
        
        vm.expectRevert(AutoLpHelper.ZeroInput.selector);
        autoLpHelper.swapEthToUsdcUsdtAndMint{value: 0}();
        
        vm.stopPrank();
    }

    function testSwapEthToUsdcUsdtAndMint_MultiplePositions() public {
        vm.startPrank(user);

        // Create first position
        uint128 liquidity1 = autoLpHelper.swapEthToUsdcUsdtAndMint{value: 0.1 ether}();
        console.log("First position liquidity:", liquidity1);
        
        // Create second position
        uint128 liquidity2 = autoLpHelper.swapEthToUsdcUsdtAndMint{value: 0.15 ether}();
        console.log("Second position liquidity:", liquidity2);
        
        // Verify both positions were created
        assertGt(liquidity1, 0, "First position should have liquidity");
        assertGt(liquidity2, 0, "Second position should have liquidity");
        assertGt(liquidity2, liquidity1, "Second position should have more liquidity");

        vm.stopPrank();
    }

    function _readPoolKey(string memory json, string memory path) internal pure returns (PoolKey memory) {
        address token0 = vm.parseJsonAddress(json, string.concat(path, ".token0"));
        address token1 = vm.parseJsonAddress(json, string.concat(path, ".token1"));
        uint256 fee = vm.parseJsonUint(json, string.concat(path, ".fee"));
        uint256 spacing = vm.parseJsonUint(json, string.concat(path, ".tickSpacing"));
        address hooks = vm.parseJsonAddress(json, string.concat(path, ".hooks"));

        return PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: uint24(fee),
            tickSpacing: int24(int256(spacing)),
            hooks: IHooks(hooks)
        });
    }
}
