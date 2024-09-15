// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/libraries/BytesLib.sol";
import "./IUniASSTaskManager.sol";
import "../lib/eigenlayer-middleware/src/ServiceManagerBase.sol";

contract UniASSServiceManager is ServiceManagerBase {
    using BytesLib for bytes;

    IUniASSTaskManager public immutable UniASSTaskManager;

    /// @notice when applied to a function, ensures that the function is only callable by the `registryCoordinator`.
    modifier onlyUniASSTaskManager() {
        require(
            msg.sender == address(UniASSTaskManager),
            "onlyUniASSTaskManager: not from credible squaring task manager"
        );
        _;
    }

    constructor(
        IAVSDirectory _avsDirectory,
        IRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry,
        IUniASSTaskManager _UniASSTaskManager
    )
        ServiceManagerBase(
            _avsDirectory,
            IPaymentCoordinator(address(0)), // inc-sq doesn't need to deal with payments
            _registryCoordinator,
            _stakeRegistry
        )
    {
        UniASSTaskManager = _UniASSTaskManager;
    }

    /// @notice Called in the event of challenge resolution, in order to forward a call to the Slasher, which 'freezes' the `operator`.
    /// @dev The Slasher contract is under active development and its interface expected to change.
    ///      We recommend writing slashing logic without integrating with the Slasher at this point in time.
    function freezeOperator(
        address operatorAddr
    ) external onlyUniASSTaskManager {
        // slasher.freezeOperator(operatorAddr);
    }
}
