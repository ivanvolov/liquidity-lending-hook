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

import {ERC721} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {BaseStrategyHook} from "@src/BaseStrategyHook.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";

/// @title ALM
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALM is BaseStrategyHook, ERC721 {
    using PoolIdLibrary for PoolKey;

    constructor(
        IPoolManager poolManager,
        Id _morphoMarketId
    ) BaseStrategyHook(poolManager) ERC721("ALM", "ALM") {
        morphoMarketId = _morphoMarketId;
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick,
        bytes calldata
    ) external override returns (bytes4) {
        console.log(">> afterInitialize");

        USDC.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
        WETH.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
        WSTETH.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
        OSQTH.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);

        WSTETH.approve(address(morpho), type(uint256).max);
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
        WSTETH.transferFrom(msg.sender, address(this), amount);

        int24 tickLower;
        int24 tickUpper;
        {
            tickLower = getCurrentTick(key.toId());
            tickUpper = ALMMathLib.tickRoundDown(
                ALMMathLib.getTickFromPrice(
                    ALMMathLib.getPriceFromTick(tickLower) * priceScalingFactor
                ),
                key.tickSpacing
            );
            console.log("Ticks, lower/upper:");
            console.logInt(tickLower);
            console.logInt(tickUpper);

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(tickUpper),
                TickMath.getSqrtPriceAtTick(tickLower),
                amount / weight
            );

            poolManager.unlock(
                abi.encodeCall(
                    this.unlockModifyPosition,
                    (key, int128(liquidity), tickLower, tickUpper)
                )
            );
        }

        morphoSupplyCollateral(WSTETH.balanceOf(address(this)));
        almId = almIdCounter;

        almInfo[almId] = ALMInfo({
            amount: amount,
            tick: getCurrentTick(key.toId()),
            tickLower: tickLower,
            tickUpper: tickUpper,
            created: block.timestamp,
            fee: getUserFee()
        });

        _mint(to, almId);
        almIdCounter++;
    }

    function withdraw(
        PoolKey calldata key,
        uint256 almId,
        address to
    ) external override {
        console.log(">> withdraw");
        if (ownerOf(almId) != msg.sender) revert NotAnALMOwner();

        //** swap all OSQTH in WSTETH
        uint256 balanceOSQTH = OSQTH.balanceOf(address(this));
        if (balanceOSQTH != 0) {
            ALMBaseLib.swapOSQTH_WSTETH_In(uint256(int256(balanceOSQTH)));
        }

        //** close position into WSTETH & USDC
        {
            (
                uint128 liquidity,
                int24 tickLower,
                int24 tickUpper
            ) = getALMPosition(key, almId);

            poolManager.unlock(
                abi.encodeCall(
                    this.unlockModifyPosition,
                    (key, -int128(liquidity), tickLower, tickUpper)
                )
            );
        }

        //** if USDC is borrowed buy extra and close the position
        morphoSync();
        Market memory m = morpho.market(morphoMarketId);
        uint256 usdcToRepay = m.totalBorrowAssets;
        MorphoPosition memory p = morpho.position(
            morphoMarketId,
            address(this)
        );

        if (usdcToRepay != 0) {
            uint256 balanceUSDC = USDC.balanceOf(address(this));
            if (usdcToRepay > balanceUSDC) {
                ALMBaseLib.swapExactOutput(
                    address(WSTETH),
                    address(USDC),
                    usdcToRepay - balanceUSDC
                );
            } else {
                ALMBaseLib.swapExactOutput(
                    address(USDC),
                    address(WSTETH),
                    balanceUSDC
                );
            }

            morphoReplay(0, p.borrowShares);
        }

        morphoWithdrawCollateral(p.collateral);
        WSTETH.transfer(to, WSTETH.balanceOf(address(this)));

        delete almInfo[almId];
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta deltas,
        bytes calldata
    ) external virtual override returns (bytes4, int128) {
        console.log(">> afterSwap");
        if (deltas.amount0() == 0 && deltas.amount1() == 0)
            revert NoSwapWillOccur();

        int24 tick = getCurrentTick(key.toId());

        if (tick > getTickLast(key.toId())) {
            console.log("> price go up...");

            morphoBorrow(uint256(int256(-deltas.amount1())), 0);
            ALMBaseLib.swapUSDC_OSQTH_In(uint256(int256(-deltas.amount1())));
        } else if (tick < getTickLast(key.toId())) {
            console.log("> price go down...");

            MorphoPosition memory p = morpho.position(
                morphoMarketId,
                address(this)
            );
            if (p.borrowShares != 0) {
                ALMBaseLib.swapOSQTH_USDC_Out(
                    uint256(int256(deltas.amount1()))
                );

                morphoReplay(uint256(int256(deltas.amount1())), 0);
            }
        } else {
            console.log("> price not changing...");
        }

        setTickLast(key.toId(), tick);
        return (ALM.afterSwap.selector, 0);
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }
}
