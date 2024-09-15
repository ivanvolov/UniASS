// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@eigenlayer-middleware/src/libraries/BN254.sol";

interface IUniASSTaskManager {
    // EVENTS
    event NewTaskCreated(uint32 indexed taskIndex, uint256 optionId);
    event TaskResponded(
        TaskResponse taskResponse,
        TaskResponseMetadata taskResponseMetadata
    );
    event TaskCompleted(uint32 indexed taskIndex);

    struct Task {
        uint256 optionId;
        address firstResponder;
        uint256 created;
    }
    struct TaskResponse {
        uint32 referenceTaskIndex;
        uint256 optionId;
    }
    struct TaskResponseMetadata {
        uint256 optionId;
        uint256 timestamp;
    }

    // FUNCTIONS
    function createNewTask(uint256 optionId, address firstResponder) external;

    function taskNumber() external view returns (uint32);
}
