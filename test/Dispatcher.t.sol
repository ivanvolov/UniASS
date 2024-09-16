// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ASSHook} from "@src/ASSHook.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {IASS} from "@src/interfaces/IASS.sol";

import {UniASSTaskManager} from "@src/avs/UniASSTaskManager.sol";
import {IUniASSTaskManager} from "@src/avs/IUniASSTaskManager.sol";
import {UniASSServiceManager} from "@src/avs/UniASSServiceManager.sol";
import {IRegistryCoordinator} from "@eigenlayer-middleware/src/interfaces/IRegistryCoordinator.sol";
import {IPauserRegistry} from "@eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {BLSMockAVSDeployer} from "@eigenlayer-middleware/test/utils/BLSMockAVSDeployer.sol";
import {TransparentUpgradeableProxy} from "@eigenlayer-middleware/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {HookTestBase} from "./libraries/HookTestBase.sol";

import "forge-std/console.sol";

contract DispatcherTest is HookTestBase {
    UniASSServiceManager sm;
    UniASSServiceManager smImplementation;
    UniASSTaskManager tm;
    UniASSTaskManager tmImplementation;
    BLSMockAVSDeployer avsDeployer;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint32 public constant TASK_RESPONSE_WINDOW_BLOCK = 30;
    address aggregator =
        address(uint160(uint256(keccak256(abi.encodePacked("aggregator")))));
    address generator =
        address(uint160(uint256(keccak256(abi.encodePacked("generator")))));

    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using TestAccountLib for TestAccount;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(19_955_703);
        deploy_avs_magic();

        deployFreshManagerAndRouters();

        labelTokens();
        init_hook();
        create_and_approve_accounts();

        vm.prank(tm.owner());
        tm.setDispatcherHook(address(hook));

        vm.prank(swapper.addr);
        TOKEN1.approve(address(tm), type(uint256).max);
        vm.prank(swapper.addr);
        TOKEN2.approve(address(tm), type(uint256).max);
    }

    function test_addLiquidity() public {
        vm.startPrank(alice.addr);
        deal(address(TOKEN1), address(alice.addr), 100 ether);
        deal(address(TOKEN2), address(alice.addr), 100 ether);
        assertEqBalanceState(alice.addr, 100 ether, 100 ether, 0);

        // Some liquidity from -60 to +60 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        // Some liquidity from -120 to +120 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        // some liquidity for full range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        vm.stopPrank();
    }

    function test_tx_signing() public {
        vm.startPrank(swapper.addr);
        uint256 amountOut = 1 ether;
        IASS.SwapTransactionData memory data = IASS.SwapTransactionData(
            swapper.addr,
            key,
            IPoolManager.SwapParams(
                true, // TOKEN1 -> TOKEN2
                int256(amountOut),
                TickMath.MIN_SQRT_PRICE + 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES,
            address(TOKEN1),
            address(TOKEN2)
        );
        bytes32 txHash = hook.hashSwapTransactionData(data);
        bytes memory signature = swapper.signPacked(txHash);

        bool isValid = hook.verifySignature(swapper.addr, txHash, signature);
        assertTrue(isValid);

        vm.stopPrank();
    }

    function test_CreateNewSwapTask_invalid_signature() public {
        IASS.SwapTransactionData[]
            memory swapTransactions = new IASS.SwapTransactionData[](1);
        IASS.SwapTransactionData memory data = IASS.SwapTransactionData(
            swapper.addr,
            key,
            IPoolManager.SwapParams(
                true, // TOKEN1 -> TOKEN2
                -int256(1 ether),
                TickMath.MIN_SQRT_PRICE + 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES,
            address(TOKEN1),
            address(TOKEN2)
        );
        swapTransactions[0] = data;

        bytes[] memory transactionSignatures = new bytes[](1);
        transactionSignatures[0] = "sdskds;sdd;s";

        vm.prank(generator);
        vm.expectRevert();
        tm.createSwapTask(swapTransactions, transactionSignatures);
    }

    function test_CreateNewSwapTask_sender_mismatch() public {
        IASS.SwapTransactionData[]
            memory swapTransactions = new IASS.SwapTransactionData[](1);
        IASS.SwapTransactionData memory data = IASS.SwapTransactionData(
            alice.addr,
            key,
            IPoolManager.SwapParams(
                true, // TOKEN1 -> TOKEN2
                -int256(1 ether),
                TickMath.MIN_SQRT_PRICE + 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES,
            address(TOKEN1),
            address(TOKEN2)
        );
        swapTransactions[0] = data;

        bytes[] memory transactionSignatures = new bytes[](1);
        transactionSignatures[0] = swapper.signPacked(
            hook.hashSwapTransactionData(swapTransactions[0])
        );

        vm.prank(generator);
        vm.expectRevert();
        tm.createSwapTask(swapTransactions, transactionSignatures);
    }

    function test_CreateNewSwapTask()
        public
        returns (IUniASSTaskManager.Task memory)
    {
        IASS.SwapTransactionData[]
            memory swapTransactions = new IASS.SwapTransactionData[](1);
        IASS.SwapTransactionData memory data = IASS.SwapTransactionData(
            swapper.addr,
            key,
            IPoolManager.SwapParams(
                true, // TOKEN1 -> TOKEN2
                -int256(1 ether),
                TickMath.MIN_SQRT_PRICE + 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES,
            address(TOKEN1),
            address(TOKEN2)
        );
        swapTransactions[0] = data;

        bytes[] memory transactionSignatures = new bytes[](1);
        transactionSignatures[0] = swapper.signPacked(
            hook.hashSwapTransactionData(swapTransactions[0])
        );

        vm.prank(generator);
        IUniASSTaskManager.Task memory task = tm.createSwapTask(
            swapTransactions,
            transactionSignatures
        );
        assertEq(tm.latestTaskNum(), 1);
        return task;
    }

    function test_watchtower_rebalance() public {
        test_addLiquidity();

        IUniASSTaskManager.Task memory task = test_CreateNewSwapTask();

        deal(address(TOKEN1), address(swapper.addr), 1 ether);
        assertEqBalanceState(swapper.addr, 1 ether, 0);
        IUniASSTaskManager.TaskResponse memory taskResponse = IUniASSTaskManager
            .TaskResponse(0, address(router));
        vm.prank(aggregator);
        tm.respondToTask(task, taskResponse);
    }

    // -- Helpers --
    function init_hook() internal {
        router = new HookEnabledSwapRouter(manager);

        address hookAddress = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG)
        );
        deployCodeTo("ASSHook.sol", abi.encode(manager), hookAddress);
        ASSHook _hook = ASSHook(hookAddress);

        (key, ) = initPool(
            Currency.wrap(address(TOKEN1)),
            Currency.wrap(address(TOKEN2)),
            _hook,
            3000,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );

        hook = IASS(hookAddress);

        hook.changeDispatcher(address(router), hookAddress);
    }

    function deploy_avs_magic() internal {
        emit log("Setting up BLSMockAVSDeployer");
        avsDeployer = new BLSMockAVSDeployer();
        avsDeployer._setUpBLSMockAVSDeployer();
        emit log("BLSMockAVSDeployer set up");

        address registryCoordinator = address(
            avsDeployer.registryCoordinator()
        );
        address proxyAdmin = address(avsDeployer.proxyAdmin());
        address pauserRegistry = address(avsDeployer.pauserRegistry());
        address registryCoordinatorOwner = avsDeployer
            .registryCoordinatorOwner();

        emit log_named_address("Registry Coordinator", registryCoordinator);
        emit log_named_address("Proxy Admin", proxyAdmin);
        emit log_named_address("Pauser Registry", pauserRegistry);
        emit log_named_address(
            "Registry Coordinator Owner",
            registryCoordinatorOwner
        );

        emit log("Deploying UniASSTaskManager implementation");
        tmImplementation = new UniASSTaskManager(
            IRegistryCoordinator(registryCoordinator),
            TASK_RESPONSE_WINDOW_BLOCK
        );
        emit log("UniASSTaskManager implementation deployed");

        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        emit log("Deploying TransparentUpgradeableProxy for UniASSTaskManager");
        tm = UniASSTaskManager(
            address(
                new TransparentUpgradeableProxy(
                    address(tmImplementation),
                    proxyAdmin,
                    abi.encodeWithSelector(
                        tm.initialize.selector,
                        pauserRegistry,
                        registryCoordinatorOwner,
                        aggregator,
                        generator
                    )
                )
            )
        );
        emit log("TransparentUpgradeableProxy for UniASSTaskManager deployed");
    }
}
