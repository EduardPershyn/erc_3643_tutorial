// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IModule} from "../interfaces/IModule.sol";

/// @title AbstractModule — shared plumbing for compliance modules.
/// @notice Handles the compliance binding + auth on action hooks, so concrete
///         modules only implement their rule (`moduleCheck`) and, if stateful,
///         the internal `_*Action` overrides.
///
/// Simplification vs. T-REX: config functions here are called directly by the
/// module's `owner` (Ownable), instead of routed through the compliance's
/// `callModuleFunction`. Clearer for study; the check/hook contract is the same.
abstract contract AbstractModule is IModule, Ownable {
    /// @notice The single ModularCompliance allowed to call the action hooks.
    address public compliance;

    event ComplianceBound(address indexed compliance);

    constructor() Ownable(msg.sender) {}

    modifier onlyCompliance() {
        require(compliance != address(0) && msg.sender == compliance, "Module: caller is not the bound compliance");
        _;
    }

    function bindCompliance(address compliance_) external onlyOwner {
        require(compliance_ != address(0), "Module: zero compliance");
        compliance = compliance_;
        emit ComplianceBound(compliance_);
    }

    // action hooks: external entry (auth) -> internal virtual (behavior)
    function moduleTransferAction(address from, address to, uint256 amount) external override onlyCompliance {
        _transferAction(from, to, amount);
    }

    function moduleMintAction(address to, uint256 amount) external override onlyCompliance {
        _mintAction(to, amount);
    }

    function moduleBurnAction(address from, uint256 amount) external override onlyCompliance {
        _burnAction(from, amount);
    }

    // stateless modules leave these as no-ops; stateful ones override.
    function _transferAction(address from, address to, uint256 amount) internal virtual {}
    function _mintAction(address to, uint256 amount) internal virtual {}
    function _burnAction(address from, uint256 amount) internal virtual {}

    // `moduleCheck` and `name` remain abstract — each module defines its rule.
}
