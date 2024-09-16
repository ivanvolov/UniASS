// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IASS} from "@src/interfaces/IASS.sol";

import {TestERC20} from "v4-core/test/TestERC20.sol";
import {Deployers} from "v4-core-test/utils/Deployers.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

abstract contract HookTestBase is Test, Deployers {
    using TestAccountLib for TestAccount;
    using CurrencyLibrary for Currency;

    IASS hook;

    TestERC20 TOKEN1;
    TestERC20 TOKEN2;

    TestAccount alice;
    TestAccount swapper;
    TestAccount swapper2;

    HookEnabledSwapRouter router;

    function labelTokens() public {
        TOKEN1 = new TestERC20(0);
        vm.label(address(TOKEN1), "TOKEN1");
        TOKEN2 = new TestERC20(0);
        vm.label(address(TOKEN2), "TOKEN2");
    }

    function create_and_approve_accounts() public {
        alice = TestAccountLib.createTestAccount("alice");
        swapper = TestAccountLib.createTestAccount("swapper");
        swapper2 = TestAccountLib.createTestAccount("swapper2");

        vm.startPrank(alice.addr);
        batchApprove(TOKEN1);
        batchApprove(TOKEN2);
        vm.stopPrank();

        vm.startPrank(swapper.addr);
        TOKEN1.approve(address(router), type(uint256).max);
        TOKEN2.approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper2.addr);
        TOKEN1.approve(address(router), type(uint256).max);
        TOKEN2.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function batchApprove(TestERC20 token) public {
        address[10] memory toApprove = [
            address(swapRouter),
            address(hook),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(manager),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor())
        ];
        for (uint256 i = 0; i < toApprove.length; i++) {
            token.approve(toApprove[i], type(uint256).max);
        }
    }

    // -- Uniswap V4 -- //

    function swapTOKEN2_TOKEN1_Out(uint256 amountOut) public {
        vm.prank(swapper.addr);
        router.swap(
            key,
            IPoolManager.SwapParams(
                false, // TOKEN2 -> TOKEN1
                int256(amountOut),
                TickMath.MAX_SQRT_PRICE - 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    function swapTOKEN1_TOKEN2_Out(uint256 amountOut) public {
        vm.prank(swapper.addr);
        router.swap(
            key,
            IPoolManager.SwapParams(
                true, // TOKEN1 -> TOKEN2
                int256(amountOut),
                TickMath.MIN_SQRT_PRICE + 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    // -- Custom assertions -- //

    function assertEqBalanceStateZero(address owner) public view {
        assertEqBalanceState(owner, 0, 0, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceTOKEN1,
        uint256 _balanceTOKEN2
    ) public view {
        assertEqBalanceState(owner, _balanceTOKEN1, _balanceTOKEN2, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceTOKEN1,
        uint256 _balanceTOKEN2,
        uint256 _balanceETH
    ) public view {
        assertApproxEqAbs(
            TOKEN1.balanceOf(owner),
            _balanceTOKEN1,
            10,
            "Balance TOKEN1 not equal"
        );
        assertApproxEqAbs(
            TOKEN2.balanceOf(owner),
            _balanceTOKEN2,
            10,
            "Balance TOKEN2 not equal"
        );

        assertApproxEqAbs(
            owner.balance,
            _balanceETH,
            10,
            "Balance ETH not equal"
        );
    }
}
