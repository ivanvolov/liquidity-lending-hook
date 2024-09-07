// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";

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
        uint256 amount,
        address to
    ) external override returns (uint256 almId) {
        console.log(">> deposit");
        if (amount == 0) revert ZeroLiquidity();
        WETH.transferFrom(msg.sender, address(this), amount);

        morphoSupplyCollateral(bUSDCmId, WETH.balanceOf(address(this)));
        almId = almIdCounter;

        liquidity = 1518129116516325613903; //TODO: make not mock

        // almInfo[almId] = ALMInfo({
        //     amount: amount,
        //     tick: getCurrentTick(key.toId()),
        //     tickLower: tickLower,
        //     tickUpper: tickUpper,
        //     created: block.timestamp,
        //     fee: getUserFee()
        // });

        // _mint(to, almId);
        // almIdCounter++;
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
            // If user is selling Token 0 and buying Token 1 (USDC => WETH)
            // TLDR: Here we got USDC and save it on balance. And just give our ETH back to USER.
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 wethOut,
                uint256 usdcIn
            ) = getZeroForOneDeltas(params.amountSpecified);
            console.log("> usdcIn", usdcIn);
            console.log("> wethOut", wethOut);

            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take actual ERC20 Token 0 from the PM and keep it in the hook and create an equivalent credit for that Token 0 since it is ours!
            key.currency0.take(poolManager, address(this), usdcIn, false);
            morphoSupplyCollateral(bWETHmId, usdcIn);

            // We don't have token 1 on our account yet, so we need to withdraw WETH from the Morpho.
            // We also need to create a debit so user could take it back from the PM.
            morphoWithdrawCollateral(bUSDCmId, wethOut);
            key.currency1.settle(poolManager, address(this), wethOut, false);

            return (this.beforeSwap.selector, beforeSwapDelta, 0);
        } else {
            console.log("> WETH price go down...");
            // If user is selling Token 1 and buying Token 0 (WETH => USDC)
            // TLDR: Here we borrow USDC at Morpho and give it back.

            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 wethIn,
                uint256 usdcOut
            ) = getOneForZeroDeltas(params.amountSpecified);
            console.log("> usdcOut", usdcOut);
            console.log("> wethIn", wethIn);

            // Put extra ETH to Morpho
            key.currency1.take(poolManager, address(this), wethIn, false);
            morphoSupplyCollateral(bUSDCmId, wethIn);

            // Ensure we have enough USDC. Redeem from reserves and borrow if needed.
            redeemAndBorrow(usdcOut);
            logBalances();
            console.log("(4)");
            key.currency0.settle(poolManager, address(this), usdcOut, false);
            console.log("(5)");

            return (this.beforeSwap.selector, beforeSwapDelta, 0);
        }
    }

    //TODO: this could be wrapped into one function, but let it be explicit till the end of the development
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

    function redeemAndBorrow(uint256 usdcOut) internal {
        uint256 usdcCollateral = supplyAssets(bWETHmId, address(this));
        console.log("usdcCollateral", usdcCollateral);
        if (usdcCollateral > 0) {
            if (usdcCollateral > usdcOut) {
                morphoWithdrawCollateral(bWETHmId, usdcOut);
            } else {
                console.log("(1)");
                morphoWithdrawCollateral(bWETHmId, usdcCollateral);
                console.log("(2)");
                morphoBorrow(bUSDCmId, usdcOut - usdcCollateral, 0);
            }
        } else {
            console.log("(3)");
            morphoBorrow(bUSDCmId, usdcOut, 0);
        }
    }
}
