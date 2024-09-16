// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {BLSApkRegistry} from "@eigenlayer-middleware/src/BLSApkRegistry.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {RegistryCoordinator} from "@eigenlayer-middleware/src/RegistryCoordinator.sol";
import {BLSSignatureChecker, IRegistryCoordinator} from "@eigenlayer-middleware/src/BLSSignatureChecker.sol";
import {OperatorStateRetriever} from "@eigenlayer-middleware/src/OperatorStateRetriever.sol";
import "@eigenlayer-middleware/src/libraries/BN254.sol";
import "./IUniASSTaskManager.sol";

import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import "@src/interfaces/IASS.sol";

import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import "forge-std/console.sol";

contract UniASSTaskManager is
    Initializable,
    OwnableUpgradeable,
    Pausable,
    BLSSignatureChecker,
    OperatorStateRetriever,
    IUniASSTaskManager
{
    using BN254 for BN254.G1Point;

    error OrderSignatureMismatch();

    // The number of blocks from the task initialization within which the aggregator has to respond to
    uint32 public immutable TASK_RESPONSE_WINDOW_BLOCK = 100;

    address public constant poolManager =
        0x1aF7f588A501EA2B5bB3feeFA744892aA2CF00e6;
    /* STORAGE */
    // The latest task index
    uint32 public latestTaskNum;
    address public aggregator;
    address public generator;

    IASS public assHook;

    mapping(uint32 => bytes32) public allTaskHashes;

    // mapping of task indices to hash of abi.encode(taskResponse, taskResponseMetadata)
    mapping(uint32 => bytes32) public allTaskResponses;

    modifier onlyAggregator() {
        require(msg.sender == aggregator, "Aggregator must be the caller");
        _;
    }

    // onlyTaskGenerator is used to restrict createNewTask from only being called by a permissioned entity
    // in a real world scenario, this would be removed by instead making createNewTask a payable function
    modifier onlyTaskGenerator() {
        require(msg.sender == generator, "Task generator must be the caller");
        _;
    }

    constructor(
        IRegistryCoordinator _registryCoordinator,
        uint32 _taskResponseWindowBlock
    ) BLSSignatureChecker(_registryCoordinator) {
        TASK_RESPONSE_WINDOW_BLOCK = _taskResponseWindowBlock;
    }

    function initialize(
        IPauserRegistry _pauserRegistry,
        address initialOwner,
        address _aggregator,
        address _generator
    ) public initializer {
        _initializePauser(_pauserRegistry, UNPAUSE_ALL);
        _transferOwnership(initialOwner);
        aggregator = _aggregator;
        generator = _generator;
    }

    function setDispatcherHook(address _assHook) external onlyOwner {
        assHook = IASS(_assHook);
    }

    function setGenerator(address newGenerator) external onlyTaskGenerator {
        generator = newGenerator;
    }

    function createSwapTask(
        IASS.SwapTransactionData[] memory swapTransactions,
        bytes[] memory transactionSignatures
    ) external onlyTaskGenerator returns (Task memory) {
        for (uint256 i = 0; i < swapTransactions.length; i++) {
            IASS.SwapTransactionData memory data = swapTransactions[i];
            if (
                !assHook.verifyOrder(
                    data.sender,
                    data,
                    transactionSignatures[i]
                )
            ) revert OrderSignatureMismatch();
            IERC20Minimal(data.token0).approve(poolManager, type(uint256).max);
            IERC20Minimal(data.token1).approve(poolManager, type(uint256).max);
        }

        return _createNewTask(swapTransactions, transactionSignatures);
    }

    /* FUNCTIONS */
    // NOTE: this function creates new auction task, assigns it a taskId
    function createNewTask(
        IASS.SwapTransactionData[] memory swapTransactions,
        bytes[] memory transactionSignatures
    ) public onlyTaskGenerator {
        _createNewTask(swapTransactions, transactionSignatures);
    }

    function _createNewTask(
        IASS.SwapTransactionData[] memory swapTransactions,
        bytes[] memory transactionSignatures
    ) internal returns (Task memory) {
        console.log("createNewTask");
        // create a new task struct
        Task memory newTask;
        newTask.swapTransactions = swapTransactions;
        newTask.transactionSignatures = transactionSignatures;
        newTask.created = block.number;

        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));

        emit NewTaskCreated(latestTaskNum, swapTransactions.length);

        latestTaskNum = latestTaskNum + 1;
        return newTask;
    }

    // NOTE: this function responds to existing tasks.
    function respondToTask(
        Task calldata task,
        TaskResponse calldata taskResponse
    ) external onlyAggregator {
        require(
            keccak256(abi.encode(task)) ==
                allTaskHashes[taskResponse.referenceTaskIndex],
            "supplied task does not match the one recorded in the contract"
        );
        require(
            allTaskResponses[taskResponse.referenceTaskIndex] == bytes32(0),
            "Aggregator has already responded to the task"
        );

        getSwapAmountsIn(task.swapTransactions);
        dispatchAllSwap(task.swapTransactions, taskResponse);

        TaskResponseMetadata memory taskResponseMetadata = TaskResponseMetadata(
            block.timestamp
        );
        // updating the storage with task responsea
        allTaskResponses[taskResponse.referenceTaskIndex] = keccak256(
            abi.encode(taskResponse, taskResponseMetadata)
        );

        // emitting event
        emit TaskResponded(taskResponse, taskResponseMetadata);
    }

    function getSwapAmountsIn(
        IASS.SwapTransactionData[] memory swapTransactions
    ) internal {
        for (uint256 i = 0; i < swapTransactions.length; i++) {
            IASS.SwapTransactionData memory data = swapTransactions[i];
            uint256 amountSpecified = data.params.amountSpecified < 0
                ? uint256(-data.params.amountSpecified)
                : uint256(data.params.amountSpecified);
            // console.log(">", amountSpecified);
            // console.log(">", data.params.zeroForOne);
            if (data.params.zeroForOne == true) {
                IERC20Minimal(data.token0).transferFrom(
                    data.sender,
                    address(this),
                    amountSpecified
                );
            } else {
                IERC20Minimal(data.token1).transferFrom(
                    data.sender,
                    address(this),
                    amountSpecified
                );
            }
        }
    }

    function dispatchAllSwap(
        IASS.SwapTransactionData[] memory swapTransactions,
        TaskResponse calldata taskResponse
    ) internal {
        for (uint256 i = 0; i < swapTransactions.length; i++) {
            IASS.SwapTransactionData memory data = swapTransactions[i];
            BalanceDelta delta = HookEnabledSwapRouter(taskResponse.router)
                .swap(data.key, data.params, data.testSettings, data.hookData);

            if (data.params.zeroForOne == true) {
                IERC20Minimal(data.token1).transfer(
                    data.sender,
                    uint256(uint128(delta.amount1()))
                );
            } else {
                IERC20Minimal(data.token0).transfer(
                    data.sender,
                    uint256(uint128(delta.amount0()))
                );
            }
        }
    }

    function taskNumber() external view returns (uint32) {
        return latestTaskNum;
    }

    function getTaskResponseWindowBlock() external view returns (uint32) {
        return TASK_RESPONSE_WINDOW_BLOCK;
    }
}
