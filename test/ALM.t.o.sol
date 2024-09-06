// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// import {Hooks} from "v4-core/libraries/Hooks.sol";
// import {TickMath} from "v4-core/libraries/TickMath.sol";
// import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
// import {ALMTestBase} from "@test/libraries/ALMTestBase.sol";

// import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
// import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
// import {ALM} from "@src/ALM.sol";
// import {IALM} from "@src/interfaces/IALM.sol";

// contract ALMTest is ALMTestBase {
//     using PoolIdLibrary for PoolId;
//     using CurrencyLibrary for Currency;

//     function setUp() public {
//         deployFreshManagerAndRouters();

//         labelTokens();
//         create_and_seed_morpho_market();
//         init_hook();
//         create_and_approve_accounts();
//     }

//     // function test_morpho_blue_market() public {
//     //     vm.startPrank(alice.addr);

//     //     // ** Supply collateral
//     //     deal(address(WSTETH), address(alice.addr), 1 ether);
//     //     morpho.supplyCollateral(
//     //         morpho.idToMarketParams(marketId),
//     //         1 ether,
//     //         alice.addr,
//     //         ""
//     //     );

//     //     assertEqMorphoState(alice.addr, 0, 0, 1 ether);
//     //     assertEqBalanceStateZero(alice.addr);

//     //     // ** Borrow
//     //     (, uint256 shares) = morpho.borrow(
//     //         morpho.idToMarketParams(marketId),
//     //         1000 * 1e6,
//     //         0,
//     //         alice.addr,
//     //         alice.addr
//     //     );

//     //     assertEqMorphoState(alice.addr, 0, shares, 1 ether);
//     //     assertEqBalanceState(alice.addr, 0, 1000 * 1e6);
//     //     vm.stopPrank();
//     // }

//     function test_deposit() public {
//         uint256 amountToDeposit = 100 ether;
//         deal(address(WETH), address(alice.addr), amountToDeposit);
//         vm.prank(alice.addr);
//         almId = hook.deposit(key, amountToDeposit, alice.addr);

//         // assertALMV4PositionLiquidity(almId, 11433916692172150);
//         assertEqBalanceStateZero(alice.addr);
//         assertEqBalanceStateZero(address(hook));
//         assertEqMorphoState(address(hook), 0, 0, amountToDeposit);
//         // IALM.ALMInfo memory info = hook.getALMInfo(almId);
//         // assertEq(info.fee, 1e16);
//     }

//     // function test_deposit_withdraw_not_alm_owner_revert() public {
//     //     test_deposit();

//     //     vm.expectRevert(IALM.NotAnALMOwner.selector);
//     //     hook.withdraw(key, 0, alice.addr);
//     // }

//     // function test_deposit_withdraw() public {
//     //     test_deposit();

//     //     vm.prank(alice.addr);
//     //     hook.withdraw(key, 0, alice.addr);

//     //     assertEqBalanceStateZero(address(hook));
//     //     assertEqBalanceState(alice.addr, 100 ether, 0);
//     //     assertALMV4PositionLiquidity(almId, 0);
//     //     assertEqMorphoState(address(hook), 0, 0, 0);
//     // }

//     // function test_swap_price_down_revert() public {
//     //     test_deposit();

//     //     deal(address(WSTETH), address(swapper.addr), 1 ether);
//     //     //TODO: fix this test if needed
//     //     // vm.expectRevert(IALM.NoSwapWillOccur.selector);
//     //     // swapWSTETH_USDC_Out(1 ether);
//     // }

//     function test_swap_price_up() public {
//         test_deposit();

//         deal(address(USDC), address(swapper.addr), 1 ether);

//         swapUSDC_WETH_Out(1 ether);

//         console.log(USDC.balanceOf(address(hook)));
//         console.log(WETH.balanceOf(address(manager)));

//         // assertEqBalanceState(swapper.addr, 1 ether, 0);
//         // assertEqBalanceState(address(hook), 0, 0, 0, 16851686274526807531);
//         // assertEqMorphoState(address(hook), 0, 4513632092000000, 50 ether);
//     }

//     // function test_swap_price_up_then_down() public {
//     //     test_swap_price_up();

//     //     swapWSTETH_USDC_Out(4513632092 / 2);

//     //     assertEqBalanceState(swapper.addr, 501269034773216656, 4513632092 / 2);
//     //     assertEqBalanceState(address(hook), 0, 0, 0, 8389745616890331647);
//     //     assertEqMorphoState(address(hook), 0, 2256816046000000, 50 ether);
//     // }

//     // function test_swap_price_up_then_withdraw() public {
//     //     test_swap_price_up();

//     //     vm.prank(alice.addr);
//     //     hook.withdraw(key, 0, alice.addr);

//     //     assertEqBalanceStateZero(address(hook));
//     //     assertEqBalanceState(alice.addr, 99999472645338963870, 0);
//     //     assertALMV4PositionLiquidity(almId, 0);
//     //     assertEqMorphoState(address(hook), 0, 0, 0);
//     // }

//     // -- Helpers --

//     function init_hook() internal {
//         router = new HookEnabledSwapRouter(manager);

//         address hookAddress = address(
//             uint160(
//                 Hooks.BEFORE_SWAP_FLAG |
//                     Hooks.AFTER_SWAP_FLAG |
//                     Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
//                     Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
//                     Hooks.AFTER_INITIALIZE_FLAG
//             )
//         );
//         deployCodeTo("ALM.sol", abi.encode(manager, marketId), hookAddress);
//         ALM _hook = ALM(hookAddress);

//         uint160 initialSQRTPrice = TickMath.getSqrtPriceAtTick(-192232);

//         //TODO: remove block binding in tests, it could be not needed. But do it after oracles
//         (key, ) = initPool(
//             Currency.wrap(address(USDC)), //TODO: this sqrt price could be fck, recalculate it
//             Currency.wrap(address(WETH)),
//             _hook,
//             200,
//             initialSQRTPrice,
//             ZERO_BYTES
//         );

//         hook = IALM(hookAddress);
//     }

//     function create_and_seed_morpho_market() internal {
//         create_morpho_market(
//             address(USDC),
//             address(WETH),
//             915000000000000000,
//             4487851340816804029821232973 //4487 usdc for eth
//         );

//         provideLiquidityToMorpho(address(USDC), 10000 * 1e6);
//     }
// }
