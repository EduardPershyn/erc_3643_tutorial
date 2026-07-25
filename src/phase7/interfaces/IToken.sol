// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IIdentityRegistry} from "../../phase5/interfaces/IIdentityRegistry.sol";
import {ICompliance} from "../../phase6/interfaces/ICompliance.sol";

/// @title IToken — the ERC-3643 permissioned token.
/// @notice ERC-20 plus: identity-gated transfers, a compliance engine, and
///         agent controls (freeze / forced transfer / mint / burn / pause).
interface IToken is IERC20 {
    event IdentityRegistrySet(address indexed identityRegistry);
    event ComplianceSet(address indexed compliance);
    event AddressFrozen(address indexed account, bool indexed frozen, address indexed by);
    event TokensFrozen(address indexed account, uint256 amount);
    event TokensUnfrozen(address indexed account, uint256 amount);

    // wiring (owner)
    function setIdentityRegistry(IIdentityRegistry identityRegistry_) external;
    function setCompliance(ICompliance compliance_) external;
    function identityRegistry() external view returns (IIdentityRegistry);
    function compliance() external view returns (ICompliance);

    // supply (agent)
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;

    // enforcement (agent)
    function forcedTransfer(address from, address to, uint256 amount) external returns (bool);
    function setAddressFrozen(address account, bool frozen) external;
    function freezePartialTokens(address account, uint256 amount) external;
    function unfreezePartialTokens(address account, uint256 amount) external;
    function pause() external;
    function unpause() external;

    // views
    function isFrozen(address account) external view returns (bool);
    function getFrozenTokens(address account) external view returns (uint256);
}
