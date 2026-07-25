// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IModule — one pluggable compliance rule.
/// @notice A module answers `moduleCheck` (is this transfer allowed by MY rule?)
///         and reacts to executed transfers/mints/burns via action hooks so it
///         can keep any internal state (e.g. a holder count) in sync.
///
/// Split of concerns:
///   - moduleCheck: pure/view decision, called by ModularCompliance.canTransfer
///   - *Action hooks: state updates, called AFTER the token moves value
interface IModule {
    /// @notice Would this transfer satisfy this module's rule?
    function moduleCheck(address from, address to, uint256 amount) external view returns (bool);

    /// @notice Post-transfer state update (holder-to-holder).
    function moduleTransferAction(address from, address to, uint256 amount) external;

    /// @notice Post-mint state update.
    function moduleMintAction(address to, uint256 amount) external;

    /// @notice Post-burn state update.
    function moduleBurnAction(address from, uint256 amount) external;

    function name() external view returns (string memory);
}
