// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {BaseHook} from "@forks/BaseHook.sol";
import {IASS} from "@src/interfaces/IASS.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

/// @title App specific sequencer hook
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ASSHook is BaseHook, IASS {
    mapping(address => address) owners;
    mapping(address => address) dispatchers;

    constructor(IPoolManager poolManager) BaseHook(poolManager) {}

    function changeOwner(address newOwner, address pool) external {
        if (msg.sender != owners[pool]) revert NotOwner();
        owners[pool] = newOwner;
    }

    function changeDispatcher(address newDispatcher, address pool) external {
        if (msg.sender != owners[pool]) revert NotOwner();
        dispatchers[pool] = newDispatcher;
    }

    function afterInitialize(
        address sender,
        PoolKey calldata,
        uint160,
        int24,
        bytes calldata
    ) external virtual override returns (bytes4) {
        owners[address(this)] = sender;
        return ASSHook.afterInitialize.selector;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // Only dispatcher contract of the ASS flow could do swaps
    function beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        if (msg.sender != dispatchers[address(this)]) revert NotDispatcher();
        return (ASSHook.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }
}
