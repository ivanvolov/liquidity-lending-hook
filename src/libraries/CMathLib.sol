// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PRBMathUD60x18} from "@src/libraries/math/PRBMathUD60x18.sol";
import {FixedPointMathLib} from "@src/libraries/math/FixedPointMathLib.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";

//TODO: move this into ALMMathLib
library CMathLib {
    using FixedPointMathLib for uint256;

    function getSwapAmountsFromAmount0(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount0
    ) internal pure returns (uint256, uint256) {
        uint160 sqrtPriceNextX96 = toUint160(
            uint256(liquidity).mul(uint256(sqrtPriceCurrentX96)).div(
                uint256(liquidity) +
                    amount0.mul(uint256(sqrtPriceCurrentX96)).div(2 ** 96)
            )
        );

        return (
            LiquidityAmounts.getAmount0ForLiquidity(
                sqrtPriceNextX96,
                sqrtPriceCurrentX96,
                liquidity
            ),
            LiquidityAmounts.getAmount1ForLiquidity(
                sqrtPriceNextX96,
                sqrtPriceCurrentX96,
                liquidity
            )
        );
    }

    function getSwapAmountsFromAmount1(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount1
    ) internal pure returns (uint256, uint256) {
        uint160 sqrtPriceDeltaX96 = toUint160((amount1 * 2 ** 96) / liquidity);
        uint160 sqrtPriceNextX96 = sqrtPriceCurrentX96 + sqrtPriceDeltaX96;

        return (
            LiquidityAmounts.getAmount0ForLiquidity(
                sqrtPriceNextX96,
                sqrtPriceCurrentX96,
                liquidity
            ),
            LiquidityAmounts.getAmount1ForLiquidity(
                sqrtPriceNextX96,
                sqrtPriceCurrentX96,
                liquidity
            )
        );
    }

    function getLiquidityFromAmountsPrice(
        uint256 priceCurrent,
        uint256 priceA,
        uint256 priceB,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128) {
        uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            getSqrtPriceFromPrice(priceCurrent),
            getSqrtPriceFromPrice(priceA),
            getSqrtPriceFromPrice(priceB),
            amount0,
            amount1
        );
        return uint128(liquidity);
    }

    function getLiquidityFromAmountsSqrtPriceX96(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceUpperX96,
        uint160 sqrtPriceLowerX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128) {
        uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceCurrentX96,
            sqrtPriceUpperX96,
            sqrtPriceLowerX96,
            amount0,
            amount1
        );
        return uint128(liquidity);
    }

    function getAmountsFromLiquiditySqrtPriceX96(
        uint160 sqrtPriceNextX96,
        uint160 sqrtPriceUpperX96,
        uint160 sqrtPriceLowerX96,
        uint128 liquidity
    ) internal pure returns (uint256, uint256) {
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceNextX96,
                sqrtPriceUpperX96,
                sqrtPriceLowerX96,
                liquidity
            );
    }

    function getTickFromPrice(uint256 price) internal pure returns (int24) {
        return
            toInt24(
                (
                    (int256(PRBMathUD60x18.ln(price * 1e18)) -
                        int256(41446531673892820000))
                ) / 99995000333297
            );
    }

    // Helpers

    function getSqrtPriceFromPrice(
        uint256 price
    ) internal pure returns (uint160) {
        return getSqrtPriceAtTick(CMathLib.getTickFromPrice(price));
    }

    function getSqrtPriceAtTick(int24 tick) internal pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(tick);
    }

    function toInt24(int256 value) internal pure returns (int24) {
        require(value >= type(int24).min && value <= type(int24).max, "MH1");
        return int24(value);
    }

    function toUint160(uint256 value) internal pure returns (uint160) {
        require(value <= type(uint160).max, "MH2");
        return uint160(value);
    }
}
