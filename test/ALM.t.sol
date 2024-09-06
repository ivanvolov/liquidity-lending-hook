// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {ALMTestBase} from "@test/libraries/ALMTestBase.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {ALM} from "@src/ALM.sol";
import {IALM} from "@src/interfaces/IALM.sol";

contract ALMTest is ALMTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    function setUp() public {
        deployFreshManagerAndRouters();

        labelTokens();
        create_and_seed_morpho_markets();
        init_hook();
        create_and_approve_accounts();
    }

    function test_morpho_blue_markets() public {
        vm.startPrank(alice.addr);

        // ** Supply collateral
        deal(address(WETH), address(alice.addr), 1 ether);
        morpho.supplyCollateral(
            morpho.idToMarketParams(bUSDCmId),
            1 ether,
            alice.addr,
            ""
        );

        assertEqMorphoState(bUSDCmId, alice.addr, 0, 0, 1 ether);
        assertEqBalanceStateZero(alice.addr);

        // // ** Borrow
        // (, uint256 shares) = morpho.borrow(
        //     morpho.idToMarketParams(marketId),
        //     1000 * 1e6,
        //     0,
        //     alice.addr,
        //     alice.addr
        // );

        // assertEqMorphoState(alice.addr, 0, shares, 1 ether);
        // assertEqBalanceState(alice.addr, 0, 1000 * 1e6);
        // vm.stopPrank();
    }

    uint256 amountToDeposit = 100 ether;

    function test_deposit() public {
        deal(address(WETH), address(alice.addr), amountToDeposit);
        vm.prank(alice.addr);
        almId = hook.deposit(key, amountToDeposit, alice.addr);

        // assertALMV4PositionLiquidity(almId, 11433916692172150);
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
        assertEqMorphoState(bUSDCmId, address(hook), 0, 0, amountToDeposit);
        // IALM.ALMInfo memory info = hook.getALMInfo(almId);
        // assertEq(info.fee, 1e16);
    }

    function test_swap_price_up() public {
        test_deposit();

        deal(address(USDC), address(swapper.addr), 1 ether);
        assertEqBalanceState(swapper.addr, 0, 1 ether);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(1 ether);

        assertEqBalanceState(swapper.addr, 1 ether, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoState(bWETHmId, address(hook), 0, 0, 1 ether);
        assertEqMorphoState(
            bUSDCmId,
            address(hook),
            0,
            0,
            amountToDeposit - deltaWETH
        );
    }

    function test_swap_price_down() public {
        test_deposit();

        deal(address(WETH), address(swapper.addr), 1 ether);
        assertEqBalanceState(swapper.addr, 1 ether, 0);

        (, uint256 deltaWETH) = swapWETH_USDC_Out(1 ether);

        // assertEqBalanceState(swapper.addr, 1 ether, 0);
        // assertEqBalanceState(address(hook), 0, 0);

        // assertEqMorphoState(bWETHmId, address(hook), 0, 0, 1 ether);
        // assertEqMorphoState(
        //     bUSDCmId,
        //     address(hook),
        //     0,
        //     0,
        //     amountToDeposit - deltaWETH
        // );
    }

    // -- Helpers --

    function init_hook() internal {
        router = new HookEnabledSwapRouter(manager);

        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG
            )
        );
        deployCodeTo(
            "ALM.sol",
            abi.encode(manager, bWETHmId, bUSDCmId),
            hookAddress
        );
        ALM _hook = ALM(hookAddress);

        uint160 initialSQRTPrice = TickMath.getSqrtPriceAtTick(-192232);

        //TODO: remove block binding in tests, it could be not needed. But do it after oracles
        (key, ) = initPool(
            Currency.wrap(address(USDC)), //TODO: this sqrt price could be fck, recalculate it
            Currency.wrap(address(WETH)),
            _hook,
            200,
            initialSQRTPrice,
            ZERO_BYTES
        );

        hook = IALM(hookAddress);

        // This is needed in order to simulate proper accounting
        deal(address(USDC), address(manager), 1000 ether);
        deal(address(WETH), address(manager), 1000 ether);
    }

    function create_and_seed_morpho_markets() internal {
        address oracle = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;

        modifyMockOracle(oracle, 1 * 1e24); //4487 usdc for eth

        bUSDCmId = create_morpho_market(
            address(USDC),
            address(WETH),
            915000000000000000,
            oracle
        );

        provideLiquidityToMorpho(bUSDCmId, 1000 ether);

        bWETHmId = create_morpho_market(
            address(WETH),
            address(USDC),
            915000000000000000,
            oracle
        );

        // We won't provide WETH cause we will not borrow it from HERE. This market is only for interest mining.
    }
}
