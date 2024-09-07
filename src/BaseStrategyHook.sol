// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";

import {Position} from "v4-core/libraries/Position.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IWETH} from "@forks/IWETH.sol";
import {IMorpho, Id} from "@forks/morpho/IMorpho.sol";
import {IALM, IOracle} from "@src/interfaces/IALM.sol";
import {MorphoBalancesLib} from "@forks/morpho/libraries/MorphoBalancesLib.sol";

import {MainDemoConsumerBase} from "@redstone-finance/data-services/MainDemoConsumerBase.sol";

abstract contract BaseStrategyHook is BaseHook, MainDemoConsumerBase, IALM {
    error NotHookDeployer();
    using CurrencySettler for Currency;

    IWETH WETH = IWETH(ALMBaseLib.WETH);
    IERC20 USDC = IERC20(ALMBaseLib.USDC);

    Id public immutable bWETHmId;
    Id public immutable bUSDCmId;

    uint160 public sqrtPriceCurrent;
    uint128 public totalLiquidity;

    function calculateTVLRation(uint128 deltaLiquidity) public view returns (uint256) {
        //@ Notice: I wanted to add volatility and TVL feed to the formula but have not time to do it.

        // uint256 ethPrice = getOracleNumericValueFromTxMsg(
        //     bytes32(
        //         0x7765455448000000000000000000000000000000000000000000000000000000
        //     )
        // );
        //@ Notice: I use this here cause can't find more elegant they to mock the new oracle push function at 12 PM;)
        
        int256 ethPrice = IOracle(0xdDb6F90fFb4d3257dd666b69178e5B3c5Bf41136)
            .latestAnswer();

        uint256 ratio = (deltaLiquidity * 1e18 / totalLiquidity ) * ethPrice/ ; 
        
        console.log("ethPrice", uint256(ethPrice));
    }

    function setInitialPrise(
        uint160 initialSQRTPrice
    ) external onlyHookDeployer {
        sqrtPriceCurrent = initialSQRTPrice;
    }

    IMorpho public constant morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    bytes internal constant ZERO_BYTES = bytes("");
    address public immutable hookDeployer;

    uint256 public priceScalingFactor = 2;
    uint256 public cRatio = 2;
    uint256 public weight = 2;
    uint256 public performanceFee = 1e16;

    function setPriceScalingFactor(
        uint256 _priceScalingFactor
    ) external onlyHookDeployer {
        priceScalingFactor = _priceScalingFactor;
    }

    function setCRatio(uint256 _cRatio) external onlyHookDeployer {
        cRatio = _cRatio;
    }

    function setWeight(uint256 _weight) external onlyHookDeployer {
        weight = _weight;
    }

    function setPerformanceFee(
        uint256 _performanceFee
    ) external onlyHookDeployer {
        performanceFee = _performanceFee;
    }

    function getUserFee() public view returns (uint256) {
        return performanceFee;
    }

    mapping(PoolId => int24) lastTick;
    uint256 public almIdCounter = 0;
    mapping(uint256 => ALMInfo) almInfo;

    function getALMInfo(
        uint256 almId
    ) external view override returns (ALMInfo memory) {
        return almInfo[almId];
    }

    function getTickLast(PoolId poolId) public view override returns (int24) {
        return lastTick[poolId];
    }

    function setTickLast(PoolId poolId, int24 _tick) internal {
        lastTick[poolId] = _tick;
    }

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        hookDeployer = msg.sender;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function getCurrentTick(
        PoolId poolId
    ) public view override returns (int24) {
        (, int24 currentTick, , ) = StateLibrary.getSlot0(poolManager, poolId);
        return currentTick;
    }

    //TODO: remove in production
    function logBalances() internal view {
        console.log("> hook balances");
        if (USDC.balanceOf(address(this)) > 0)
            console.log("USDC  ", USDC.balanceOf(address(this)));
        if (WETH.balanceOf(address(this)) > 0)
            console.log("WETH  ", WETH.balanceOf(address(this)));
    }

    // --- Morpho Wrappers ---

    function morphoBorrow(
        Id morphoMarketId,
        uint256 amount,
        uint256 shares
    ) internal {
        morpho.borrow(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            shares,
            address(this),
            address(this)
        );
    }

    function morphoReplay(
        Id morphoMarketId,
        uint256 amount,
        uint256 shares
    ) internal {
        morpho.repay(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            shares,
            address(this),
            ZERO_BYTES
        );
    }

    function morphoWithdrawCollateral(
        Id morphoMarketId,
        uint256 amount
    ) internal {
        morpho.withdrawCollateral(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            address(this),
            address(this)
        );
    }

    function morphoSupplyCollateral(
        Id morphoMarketId,
        uint256 amount
    ) internal {
        morpho.supplyCollateral(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            address(this),
            ZERO_BYTES
        );
    }

    function supplyAssets(
        Id morphoMarketId,
        address owner
    ) internal view returns (uint256) {
        return
            MorphoBalancesLib.expectedSupplyAssets(
                morpho,
                morpho.idToMarketParams(morphoMarketId),
                owner
            );
    }

    function morphoSync(Id morphoMarketId) internal {
        morpho.accrueInterest(morpho.idToMarketParams(morphoMarketId));
    }

    /// @dev Only the hook deployer may call this function
    modifier onlyHookDeployer() {
        if (msg.sender != hookDeployer) revert NotHookDeployer();
        _;
    }
}
