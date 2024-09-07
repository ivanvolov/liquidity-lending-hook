// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {ALMTestBase} from "@test/libraries/ALMTestBase.sol";
import {ErrorsLib} from "@forks/morpho/libraries/ErrorsLib.sol";

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

        // ** Borrow
        uint256 borrowUSDC = 4000 * 1e6;
        (, uint256 shares) = morpho.borrow(
            morpho.idToMarketParams(bUSDCmId),
            borrowUSDC,
            0,
            alice.addr,
            alice.addr
        );

        assertEqMorphoState(bUSDCmId, alice.addr, 0, shares, 1 ether);
        assertEqBalanceState(alice.addr, 0, borrowUSDC);
        vm.stopPrank();
    }

    uint256 amountToDep = 100 ether;

    function test_deposit() public {
        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);
        almId = hook.deposit(key, amountToDep, alice.addr);

        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
        assertEqMorphoA(bUSDCmId, address(hook), 0, 0, amountToDep);
        assertEqMorphoA(bWETHmId, address(hook), 0, 0, 0);
    }

    function test_swap_price_up_in() public {
        uint256 usdcToSwap = 4487 * 1e6;
        test_deposit();

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 1 ether, 1e12);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(bWETHmId, address(hook), 0, 0, usdcToSwap);
        assertEqMorphoA(bUSDCmId, address(hook), 0, 0, amountToDep - deltaWETH);
    }

    function test_swap_price_up_out() public {
        uint256 usdcToSwapQ = 4486999802; // this should be get from quoter
        uint256 wethToGetFSwap = 1 ether;
        test_deposit();

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 1 ether, 1e1);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(bWETHmId, address(hook), 0, 0, usdcToSwapQ);
        assertEqMorphoA(bUSDCmId, address(hook), 0, 0, amountToDep - deltaWETH);
    }

    function test_swap_price_down_in() public {
        uint256 wethToSwap = 1 ether;
        test_deposit();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 4486999802);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(bWETHmId, address(hook), 0, 0, 0);
        assertEqMorphoA(
            bUSDCmId,
            address(hook),
            0,
            deltaUSDC,
            amountToDep + wethToSwap
        );
    }

    function test_swap_price_down_out() public {
        uint256 wethToSwapQ = 999999911749086355;
        uint256 usdcToGetFSwap = 4486999802;
        test_deposit();

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        // assertEqBalanceState(address(hook), 0, 0);

        // assertEqMorphoA(bWETHmId, address(hook), 0, 0, 0);
        // assertEqMorphoA(
        //     bUSDCmId,
        //     address(hook),
        //     0,
        //     deltaUSDC,
        //     amountToDep + wethToSwap
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

        uint160 initialSQRTPrice = 1182773400228691521900860642689024; // 4487 usdc for eth (but in reversed tokens order). Tick: 192228

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

        int24 deltaTick = 3000;
        hook.setBoundaries(
            initialSQRTPrice,
            192228 - deltaTick,
            192228 + deltaTick
            // 191144, // 5000 usdc for eth
            // 193376 // 4000 usdc for eth
        );

        // This is needed in order to simulate proper accounting
        deal(address(USDC), address(manager), 1000 ether);
        deal(address(WETH), address(manager), 1000 ether);
    }

    function create_and_seed_morpho_markets() internal {
        address oracle = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;

        modifyMockOracle(oracle, 4487851340816804029821232973); //4487 usdc for eth

        bUSDCmId = create_morpho_market(
            address(USDC),
            address(WETH),
            915000000000000000,
            oracle
        );

        // Providing some ETH
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
