// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IModule} from "./IModule.sol";

/// @title ICompliance — the modular compliance engine bound to a token.
/// @notice `canTransfer` is the gate the token calls before moving value;
///         `transferred`/`created`/`destroyed` are the hooks it calls AFTER,
///         so stateful modules can update. Only the bound token may call the
///         hooks; only the owner manages modules.
interface ICompliance {
    event ModuleAdded(address indexed module);
    event ModuleRemoved(address indexed module);
    event TokenBound(address indexed token);

    function bindToken(address token) external;
    function getTokenBound() external view returns (address);

    function addModule(IModule module) external;
    function removeModule(IModule module) external;
    function getModules() external view returns (IModule[] memory);

    /// @notice AND over every module: all must allow the transfer.
    function canTransfer(address from, address to, uint256 amount) external view returns (bool);

    // --- post-action hooks (token only) ---
    function transferred(address from, address to, uint256 amount) external;
    function created(address to, uint256 amount) external;
    function destroyed(address from, uint256 amount) external;
}
