// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {OptionTestBase} from "@test/libraries/OptionTestBase.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {MicroSequencer} from "@src/MicroSequencer.sol";

import {IOption} from "@src/interfaces/IOption.sol";

import {UniASSTaskManager} from "@src/avs/UniASSTaskManager.sol";
import {IUniASSTaskManager} from "@src/avs/IUniASSTaskManager.sol";
import {UniASSServiceManager} from "@src/avs/UniASSServiceManager.sol";
import {IRegistryCoordinator} from "@eigenlayer-middleware/src/interfaces/IRegistryCoordinator.sol";
import {IPauserRegistry} from "@eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {BLSMockAVSDeployer} from "@eigenlayer-middleware/test/utils/BLSMockAVSDeployer.sol";
import {TransparentUpgradeableProxy} from "@eigenlayer-middleware/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {OptionTestBase} from "./libraries/OptionTestBase.sol";

import "forge-std/console.sol";

contract UniASSTest is OptionTestBase {
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

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(19_955_703);
        deploy_avs_magic();

        deployFreshManagerAndRouters();

        labelTokens();
        create_and_seed_morpho_market();
        init_hook();
        create_and_approve_accounts();

        vm.prank(tm.owner());
        tm.setOptionHook(address(hook));
    }

    function test_CreateNewTask() public {
        vm.prank(generator);
        tm.createNewTask(0, generator);
        assertEq(tm.latestTaskNum(), 1);
    }

    function test_simulateWatchTowerEmptyCreateTasks() public {
        vm.prank(generator);
        tm.createRebalanceTask();
        assertEq(tm.latestTaskNum(), 0);
    }

    function test_deposit() public {
        uint256 amountToDeposit = 100 ether;
        deal(address(WSTETH), address(alice.addr), amountToDeposit);
        vm.prank(alice.addr);
        optionId = hook.deposit(key, amountToDeposit, alice.addr);

        assertOptionV4PositionLiquidity(optionId, 11433916692172150);
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
        assertEqMorphoState(
            address(hook),
            0,
            0,
            amountToDeposit / hook.cRatio()
        );
        IOption.OptionInfo memory info = hook.getOptionInfo(optionId);
        assertEq(info.fee, 0);
    }

    function test_swap_price_up() public {
        test_deposit();

        deal(address(USDC), address(swapper.addr), 4513632092);

        swapUSDC_WSTETH_Out(1 ether);

        assertEqBalanceState(swapper.addr, 1 ether, 0);
        assertEqBalanceState(address(hook), 0, 0, 0, 16851686274526807531);
        assertEqMorphoState(address(hook), 0, 4513632092000000, 50 ether);
    }

    function test_simulateWatchTowerCreateTasks() public {
        test_swap_price_up();

        vm.prank(generator);
        tm.createRebalanceTask();
        assertEq(tm.latestTaskNum(), 1);
    }

    function test_swap_price_up_then_watchtower_rebalance() public {
        test_swap_price_up();

        vm.prank(generator);
        tm.createRebalanceTask();
        assertEq(tm.latestTaskNum(), 1);

        vm.prank(generator);
        hook.priceRebalance(key, 0);

        assertEqBalanceState(address(hook), 0, 0);
        assertEqBalanceState(alice.addr, 0, 0);
        assertOptionV4PositionLiquidity(optionId, 0);
        assertEqMorphoState(address(hook), 0, 0, 49999736322669483551);
    }

    // -- Helpers --

    function init_hook() internal {
        router = new HookEnabledSwapRouter(manager);

        address hookAddress = address(
            uint160(
                Hooks.AFTER_SWAP_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG
            )
        );
        deployCodeTo(
            "MicroSequencer.sol",
            abi.encode(manager, marketId),
            hookAddress
        );
        MicroSequencer _hook = MicroSequencer(hookAddress);

        uint160 initialSQRTPrice = TickMath.getSqrtPriceAtTick(-192232);

        (key, ) = initPool(
            Currency.wrap(address(WSTETH)),
            Currency.wrap(address(USDC)),
            _hook,
            200,
            initialSQRTPrice,
            ZERO_BYTES
        );

        hook = IOption(hookAddress);
    }

    function create_and_seed_morpho_market() internal {
        create_morpho_market(
            address(USDC),
            address(WSTETH),
            915000000000000000,
            4487851340816804029821232973 //4487 usdc for eth
        );

        provideLiquidityToMorpho(address(USDC), 10000 * 1e6);
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
