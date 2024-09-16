// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";

interface IASS {
    error NotDispatcher();
    error NotOwner();

    struct SwapTransactionData {
        PoolKey key;
        IPoolManager.SwapParams params;
        HookEnabledSwapRouter.TestSettings testSettings;
        bytes hookData;
    }

    function hashSwapTransactionData(
        SwapTransactionData memory data
    ) external pure returns (bytes32);

    function verifySignature(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) external pure returns (bool);
}
