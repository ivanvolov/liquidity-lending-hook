// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {Id} from "@forks/morpho/IMorpho.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

import {ERC721} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {BaseStrategyHook} from "@src/BaseStrategyHook.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";
import {CMathLib} from "@src/libraries/CMathLib.sol";

/// @title ALM
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALM is BaseStrategyHook, ERC721 {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    constructor(
        IPoolManager manager,
        Id _bWETHmId,
        Id _bUSDCmId
    ) BaseStrategyHook(manager) ERC721("ALM", "ALM") {
        bWETHmId = _bWETHmId;
        bUSDCmId = _bUSDCmId;
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick,
        bytes calldata
    ) external override returns (bytes4) {
        console.log(">> afterInitialize");

        WETH.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
        USDC.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);

        WETH.approve(address(morpho), type(uint256).max);
        USDC.approve(address(morpho), type(uint256).max);

        setTickLast(key.toId(), tick);

        return ALM.afterInitialize.selector;
    }

    /// @notice  Disable adding liquidity through the PM
    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    function deposit(
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        uint160 sqrtPriceUpperX96,
        uint160 sqrtPriceLowerX96,
        address to
    ) external override returns (uint256 almId) {
        console.log(">> deposit");

        uint128 liquidity = CMathLib.getLiquidityFromAmountsSqrtPriceX96(
            sqrtPriceCurrent,
            sqrtPriceUpperX96,
            sqrtPriceLowerX96,
            amount0,
            amount1
        );

        (uint256 _amount0, uint256 _amount1) = CMathLib
            .getAmountsFromLiquiditySqrtPriceX96(
                sqrtPriceCurrent,
                sqrtPriceUpperX96,
                sqrtPriceLowerX96,
                liquidity
            );

        if (liquidity == 0) revert ZeroLiquidity();
        console.log("_amount0", _amount0);
        console.log("_amount1", _amount1);
        USDC.transferFrom(msg.sender, address(this), _amount0);
        WETH.transferFrom(msg.sender, address(this), _amount1);

        morphoSupplyCollateral(bUSDCmId, WETH.balanceOf(address(this)));
        morphoSupplyCollateral(bWETHmId, USDC.balanceOf(address(this)));

        almInfo[almIdCounter] = ALMInfo({
            liquidity: liquidity,
            sqrtPriceUpperX96: sqrtPriceUpperX96,
            sqrtPriceLowerX96: sqrtPriceLowerX96,
            amount0: _amount0,
            amount1: _amount1,
            owner: to
        });

        _mint(to, almIdCounter);
        almIdCounter++;
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }

    // Swapping
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        if (params.zeroForOne) {
            console.log("> WETH price go up...");
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 wethOut,
                uint256 usdcIn
            ) = getZeroForOneDeltas(params.amountSpecified);
            console.log("> usdcIn", usdcIn);
            console.log("> wethOut", wethOut);

            key.currency0.take(poolManager, address(this), usdcIn, false);
            morphoSupplyCollateral(bWETHmId, usdcIn);

            redeemIfNotEnough(address(WETH), wethOut, bUSDCmId);
            key.currency1.settle(poolManager, address(this), wethOut, false);

            return (this.beforeSwap.selector, beforeSwapDelta, 0);
        } else {
            console.log("> WETH price go down...");
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 wethIn,
                uint256 usdcOut
            ) = getOneForZeroDeltas(params.amountSpecified);
            console.log("> usdcOut", usdcOut);
            console.log("> wethIn", wethIn);

            key.currency1.take(poolManager, address(this), wethIn, false);
            morphoSupplyCollateral(bUSDCmId, wethIn);

            redeemIfNotEnough(address(USDC), usdcOut, bWETHmId);
            key.currency0.settle(poolManager, address(this), usdcOut, false);
            console.log("(5)");

            return (this.beforeSwap.selector, beforeSwapDelta, 0);
        }
    }

    function getZeroForOneDeltas(
        int256 amountSpecified
    )
        internal
        view
        returns (
            BeforeSwapDelta beforeSwapDelta,
            uint256 wethOut,
            uint256 usdcIn
        )
    {
        // MOCK get from current and only tick, do loop in the future
        uint128 liquidity = almInfo[0].liquidity;

        if (amountSpecified > 0) {
            console.log("> amount specified positive");
            wethOut = uint256(amountSpecified);

            (usdcIn, ) = CMathLib.getSwapAmountsFromAmount1(
                sqrtPriceCurrent,
                liquidity,
                wethOut
            );

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(wethOut)), // specified token = token1
                int128(uint128(usdcIn)) // unspecified token = token0
            );
        } else {
            console.log("> amount specified negative");

            usdcIn = uint256(-amountSpecified);

            (, wethOut) = CMathLib.getSwapAmountsFromAmount0(
                sqrtPriceCurrent,
                liquidity,
                usdcIn
            );

            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(usdcIn)), // specified token = token0
                -int128(uint128(wethOut)) // unspecified token = token1
            );
        }
    }

    function getOneForZeroDeltas(
        int256 amountSpecified
    )
        internal
        view
        returns (
            BeforeSwapDelta beforeSwapDelta,
            uint256 wethIn,
            uint256 usdcOut
        )
    {
        // MOCK get from current and only tick, do loop in the future
        uint128 liquidity = almInfo[0].liquidity;

        if (amountSpecified > 0) {
            console.log("> amount specified positive");

            usdcOut = uint256(amountSpecified);

            (, wethIn) = CMathLib.getSwapAmountsFromAmount0(
                sqrtPriceCurrent,
                liquidity,
                usdcOut
            );
            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(usdcOut)), // specified token = token0
                int128(uint128(wethIn)) // unspecified token = token1
            );
        } else {
            console.log("> amount specified negative");
            wethIn = uint256(-amountSpecified);

            (usdcOut, ) = CMathLib.getSwapAmountsFromAmount1(
                sqrtPriceCurrent,
                liquidity,
                wethIn
            );

            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(wethIn)), // specified token = token1
                -int128(uint128(usdcOut)) // unspecified token = token0
            );
        }
    }

    function redeemIfNotEnough(address token, uint256 amount, Id id) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) {
            morphoWithdrawCollateral(id, amount - balance);
        }
    }
}
