// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ALMBaseLib} from "../src/libraries/ALMBaseLib.sol";

contract ALMBaseLibTest is Test {
    address WETH;
    address WSTETH;
    address USDC;
    address OSQTH;

    function setUp() public {
        WETH = ALMBaseLib.WETH;
        vm.label(WETH, "WETH");
        WSTETH = ALMBaseLib.WSTETH;
        vm.label(WSTETH, "WSTETH");
        USDC = ALMBaseLib.USDC;
        vm.label(USDC, "USDC");
        OSQTH = ALMBaseLib.OSQTH;
        vm.label(OSQTH, "OSQTH");
    }

    function test_getFee() public view {
        assertEq(
            ALMBaseLib.getFee(WSTETH, USDC),
            ALMBaseLib.WSTETH_USDC_POOL_FEE
        );
        assertEq(
            ALMBaseLib.getFee(USDC, WSTETH),
            ALMBaseLib.WSTETH_USDC_POOL_FEE
        );

        assertEq(
            ALMBaseLib.getFee(WSTETH, WETH),
            ALMBaseLib.WSTETH_ETH_POOL_FEE
        );
        assertEq(
            ALMBaseLib.getFee(WETH, WSTETH),
            ALMBaseLib.WSTETH_ETH_POOL_FEE
        );

        assertEq(ALMBaseLib.getFee(USDC, WETH), ALMBaseLib.ETH_USDC_POOL_FEE);
        assertEq(ALMBaseLib.getFee(WETH, USDC), ALMBaseLib.ETH_USDC_POOL_FEE);

        assertEq(ALMBaseLib.getFee(WETH, OSQTH), ALMBaseLib.ETH_OSQTH_POOL_FEE);
        assertEq(ALMBaseLib.getFee(OSQTH, WETH), ALMBaseLib.ETH_OSQTH_POOL_FEE);
    }
}
