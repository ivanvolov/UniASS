// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../lib/eigenlayer-middleware/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/eigenlayer-middleware/lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "../lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import "../lib/eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {BLSApkRegistry} from "../lib/eigenlayer-middleware/src/BLSApkRegistry.sol";
import {RegistryCoordinator} from "../lib/eigenlayer-middleware/src/RegistryCoordinator.sol";
import {BLSSignatureChecker, IRegistryCoordinator} from "../lib/eigenlayer-middleware/src/BLSSignatureChecker.sol";
import {OperatorStateRetriever} from "../lib/eigenlayer-middleware/src/OperatorStateRetriever.sol";
import "../lib/eigenlayer-middleware/src/libraries/BN254.sol";
import "./IUniASSTaskManager.sol";

// import "../../../src/interfaces/IASS.sol";

import "../lib/forge-std/src/console.sol";

contract UniASSTaskManager is
    Initializable,
    OwnableUpgradeable,
    Pausable,
    BLSSignatureChecker,
    OperatorStateRetriever,
    IUniASSTaskManager
{
    using BN254 for BN254.G1Point;

    /* CONSTANT */
    // The number of blocks from the task initialization within which the aggregator has to respond to
    uint32 public immutable TASK_RESPONSE_WINDOW_BLOCK = 100;

    /* STORAGE */
    // The latest task index
    uint32 public latestTaskNum;
    address public aggregator;
    address public generator;

    IASS public optionHook;

    // mapping of task indices to all tasks hashes
    // when a task is created, task hash is stored here,
    // and responses need to pass the actual task,
    // which is hashed onchain and checked against this mapping
    mapping(uint32 => bytes32) public allTaskHashes;

    // mapping of task indices to hash of abi.encode(taskResponse, taskResponseMetadata)
    mapping(uint32 => bytes32) public allTaskResponses;

    /* MODIFIERS */
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

    function setOptionHook(address _optionHook) external onlyOwner {
        optionHook = IASS(_optionHook);
    }

    function setGenerator(address newGenerator) external onlyTaskGenerator {
        generator = newGenerator;
    }

    // Anybody could call it, but the task will be emitted for all keepers to take
    // Also the calling keeper will have a time window to respond to the task
    function createRebalanceTask() external {
        for (uint256 i = 0; i < optionHook.optionIdCounter(); i++) {
            PoolKey memory key = optionHook.getOptionInfo(i).key;
            if (optionHook.isPriceRebalance(key, i)) {
                createNewTask(i, msg.sender);
            }
        }
    }

    /* FUNCTIONS */
    // NOTE: this function creates new auction task, assigns it a taskId
    function createNewTask(uint256 optionId, address firstResponder) public {
        console.log("createNewTask");
        // create a new task struct
        Task memory newTask;
        newTask.optionId = optionId;
        newTask.firstResponder = firstResponder;
        newTask.created = block.number;

        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));

        emit NewTaskCreated(latestTaskNum, optionId);

        latestTaskNum = latestTaskNum + 1;
    }

    // NOTE: this function responds to existing tasks.
    function respondToTask(
        Task calldata task,
        TaskResponse calldata taskResponse
    ) external onlyAggregator {
        uint256 optionId = task.optionId;

        require(
            task.optionId == taskResponse.optionId,
            "Error: optionId mismatch"
        );
        require(
            keccak256(abi.encode(task)) ==
                allTaskHashes[taskResponse.referenceTaskIndex],
            "supplied task does not match the one recorded in the contract"
        );
        require(
            allTaskResponses[taskResponse.referenceTaskIndex] == bytes32(0),
            "Aggregator has already responded to the task"
        );

        // Here is the logic what allows only firstResponder to respond to the task in the given time window
        // After this anybody could respond. Also firstResponder should be penalized if not responded in time
        require(
            task.firstResponder == msg.sender &&
                block.timestamp < task.created + TASK_RESPONSE_WINDOW_BLOCK,
            "Only first responder can respond to the task"
        );

        TaskResponseMetadata memory taskResponseMetadata = TaskResponseMetadata(
            optionId,
            block.timestamp
        );
        // updating the storage with task responsea
        allTaskResponses[taskResponse.referenceTaskIndex] = keccak256(
            abi.encode(taskResponse, taskResponseMetadata)
        );

        // emitting event
        emit TaskResponded(taskResponse, taskResponseMetadata);
    }

    function taskNumber() external view returns (uint32) {
        return latestTaskNum;
    }

    function getTaskResponseWindowBlock() external view returns (uint32) {
        return TASK_RESPONSE_WINDOW_BLOCK;
    }
}
