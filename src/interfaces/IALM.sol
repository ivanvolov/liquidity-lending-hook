// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

interface IALM {
    error ZeroLiquidity();

    error AddLiquidityThroughHook();

    error InRange();

    error NotAnALMOwner();

    error NoSwapWillOccur();

    struct ALMInfo {
        uint128 liquidity;
        uint160 sqrtPriceUpperX96;
        uint160 sqrtPriceLowerX96;
        uint256 amount0;
        uint256 amount1;
        address owner;
    }

    function getALMInfo(uint256 almId) external view returns (ALMInfo memory);

    function priceScalingFactor() external view returns (uint256);

    function cRatio() external view returns (uint256);

    function weight() external view returns (uint256);

    function getTickLast(PoolId poolId) external view returns (int24);

    function deposit(
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        uint160 sqrtPriceUpperX96,
        uint160 sqrtPriceLowerX96,
        address to
    ) external returns (uint256 almId);

    function getCurrentTick(PoolId poolId) external view returns (int24);

    function setInitialPrise(uint160 initialSQRTPrice) external;

    function calculateTVLRation() external view returns (uint256);
}

interface IOracle {
    function latestAnswer() external view returns (int256);
}
