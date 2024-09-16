// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@eigenlayer-middleware/src/libraries/BN254.sol";

import {IASS} from "../interfaces/IASS.sol";

interface IUniASSTaskManager {
    // EVENTS
    event NewTaskCreated(uint32 indexed taskIndex, uint256 optionId);
    event TaskResponded(
        TaskResponse taskResponse,
        TaskResponseMetadata taskResponseMetadata
    );
    event TaskCompleted(uint32 indexed taskIndex);

    struct Task {
        IASS.SwapTransactionData[] swapTransactions;
        bytes[] transactionSignatures;
        address firstResponder;
        uint256 created;
    }

    struct TaskResponse {
        uint32 referenceTaskIndex;
        address router;
    }

    struct TaskResponseMetadata {
        uint256 timestamp;
    }

    // FUNCTIONS
    function createNewTask(
        IASS.SwapTransactionData[] memory swapTransactions,
        bytes[] memory transactionSignatures
    ) external;

    function taskNumber() external view returns (uint32);
}
