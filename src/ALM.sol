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

/// @title ALM
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALM is BaseStrategyHook, ERC721 {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    constructor(
        IPoolManager manager,
        Id _borrowWETHmarketId,
        Id _borrowUSDCmarketId
    ) BaseStrategyHook(manager) ERC721("ALM", "ALM") {
        borrowWETHmarketId = _borrowWETHmarketId;
        borrowUSDCmarketId = _borrowUSDCmarketId;
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

        morphoSupplyCollateral(
            borrowUSDCmarketId,
            WETH.balanceOf(address(this))
        );
        almId = almIdCounter;

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
        //TODO: I will put here 1-1 ration, and not uniswap curve to simplify the code until I fix this.
        //TODO: Maybe move smth into the afterSwap hook, you know

        BeforeSwapDelta beforeSwapDelta = toBeforeSwapDelta(
            int128(-params.amountSpecified), // So `specifiedAmount` = +100
            int128(params.amountSpecified) // Unspecified amount (output delta) = -100
        );

        uint256 amountInOutPositive = params.amountSpecified > 0
            ? uint256(params.amountSpecified)
            : uint256(-params.amountSpecified);
        if (params.zeroForOne) {
            console.log("> WETH price go up...");
            // If user is selling Token 0 and buying Token 1 (USDC => WETH)
            // TLDR: Here we got USDC and save it on balance. And just give our ETH back to USER.

            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take actual ERC20 Token 0 from the PM and keep it in the hook
            // and create an equivalent credit for that Token 0 since it is ours!
            key.currency0.take(
                poolManager,
                address(this),
                amountInOutPositive,
                false
            );
            morphoSupplyCollateral(borrowWETHmarketId, amountInOutPositive);

            // We don't have token 1 on our account yet, so we need to withdraw WETH from the Morpho.
            // We also need to create a debit so user could take it back from the PM.
            morphoWithdrawCollateral(borrowUSDCmarketId, amountInOutPositive);
            key.currency1.settle(
                poolManager,
                address(this),
                amountInOutPositive,
                false
            );
        } else {
            console.log("> ETH price go down...");
            // If user is selling Token 1 and buying Token 0 (WETH => USDC)
            // TLDR: Here we borrow USDC at Morpho and give it back.

            // Put extra ETH to Morpho
            key.currency1.take(
                poolManager,
                address(this),
                amountInOutPositive,
                false
            );
            morphoSupplyCollateral(borrowUSDCmarketId, amountInOutPositive);

            // If we have USDC just also give it back before borrow.
            uint256 usdcCollateral = expectedSupplyAssets(
                borrowWETHmarketId,
                address(this)
            );

            console.log("usdcCollateral", usdcCollateral);
            if (usdcCollateral > 0) {
                if (usdcCollateral > amountInOutPositive) {
                    morphoWithdrawCollateral(
                        borrowWETHmarketId,
                        amountInOutPositive
                    );
                } else {
                    console.log("(1)");
                    morphoWithdrawCollateral(
                        borrowWETHmarketId,
                        usdcCollateral
                    );
                    console.log("(2)");
                    morphoBorrow(
                        borrowUSDCmarketId,
                        amountInOutPositive - usdcCollateral,
                        0
                    );
                }
            } else {
                console.log("(3)");
                morphoBorrow(borrowUSDCmarketId, 1, 0);
            }
            console.log("(3+)");
            logBalances();
            console.log("(4)");
            key.currency0.settle(
                poolManager,
                address(this),
                amountInOutPositive,
                false
            );
        }

        return (this.beforeSwap.selector, beforeSwapDelta, 0);
    }
}
