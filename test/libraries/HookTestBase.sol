// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {MarketParamsLib} from "@forks/morpho/MarketParamsLib.sol";
import {OptionBaseLib} from "@src/libraries/OptionBaseLib.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IChainlinkOracle} from "@forks/morpho-oracles/IChainlinkOracle.sol";
import {IMorpho, MarketParams, Position as MorphoPosition, Id} from "@forks/morpho/IMorpho.sol";
import {IASS} from "@src/interfaces/IASS.sol";

import {TestERC20} from "v4-core/test/TestERC20.sol";
import {Deployers} from "v4-core-test/utils/Deployers.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";

abstract contract HookTestBase is Test, Deployers {
    using TestAccountLib for TestAccount;

    IASS hook;

    TestERC20 WSTETH;
    TestERC20 USDC;
    TestERC20 OSQTH;
    TestERC20 WETH;

    TestAccount alice;
    TestAccount swapper;

    HookEnabledSwapRouter router;

    function labelTokens() public {
        WSTETH = TestERC20(OptionBaseLib.WSTETH);
        vm.label(address(WSTETH), "WSTETH");
        USDC = TestERC20(OptionBaseLib.USDC);
        vm.label(address(USDC), "USDC");
        OSQTH = TestERC20(OptionBaseLib.OSQTH);
        vm.label(address(OSQTH), "OSQTH");
        WETH = TestERC20(OptionBaseLib.WETH);
        vm.label(address(WETH), "WETH");
    }

    function create_and_approve_accounts() public {
        alice = TestAccountLib.createTestAccount("alice");
        swapper = TestAccountLib.createTestAccount("swapper");

        vm.startPrank(alice.addr);
        WSTETH.approve(address(hook), type(uint256).max);
        USDC.approve(address(hook), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper.addr);
        WSTETH.approve(address(router), type(uint256).max);
        USDC.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    // -- Uniswap V4 -- //

    function swapUSDC_WSTETH_Out(uint256 amountOut) public {
        vm.prank(swapper.addr);
        router.swap(
            key,
            IPoolManager.SwapParams(
                false, // USDC -> WSTETH
                int256(amountOut),
                TickMath.MAX_SQRT_PRICE - 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    function swapWSTETH_USDC_Out(uint256 amountOut) public {
        vm.prank(swapper.addr);
        router.swap(
            key,
            IPoolManager.SwapParams(
                true, // WSTETH -> USDC
                int256(amountOut),
                TickMath.MIN_SQRT_PRICE + 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    // -- Custom assertions -- //

    function assertEqBalanceStateZero(address owner) public view {
        assertEqBalanceState(owner, 0, 0, 0, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceWSTETH,
        uint256 _balanceUSDC
    ) public view {
        assertEqBalanceState(owner, _balanceWSTETH, _balanceUSDC, 0, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceWSTETH,
        uint256 _balanceUSDC,
        uint256 _balanceWETH,
        uint256 _balanceOSQTH
    ) public view {
        assertEqBalanceState(
            owner,
            _balanceWSTETH,
            _balanceUSDC,
            _balanceWETH,
            _balanceOSQTH,
            0
        );
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceWSTETH,
        uint256 _balanceUSDC,
        uint256 _balanceWETH,
        uint256 _balanceOSQTH,
        uint256 _balanceETH
    ) public view {
        assertApproxEqAbs(
            USDC.balanceOf(owner),
            _balanceUSDC,
            10,
            "Balance USDC not equal"
        );
        assertApproxEqAbs(
            WETH.balanceOf(owner),
            _balanceWETH,
            10,
            "Balance WETH not equal"
        );
        assertApproxEqAbs(
            OSQTH.balanceOf(owner),
            _balanceOSQTH,
            10,
            "Balance OSQTH not equal"
        );
        assertApproxEqAbs(
            WSTETH.balanceOf(owner),
            _balanceWSTETH,
            10,
            "Balance WSTETH not equal"
        );

        assertApproxEqAbs(
            owner.balance,
            _balanceETH,
            10,
            "Balance ETH not equal"
        );
    }
}
