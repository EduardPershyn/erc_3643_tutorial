// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AgentRole} from "../common/AgentRole.sol";
import {IToken} from "./interfaces/IToken.sol";
import {IIdentityRegistry} from "../phase5/interfaces/IIdentityRegistry.sol";
import {ICompliance} from "../phase6/interfaces/ICompliance.sol";

/// @title Token — a minimal ERC-3643 security token.
/// @notice The final assembly. A holder-to-holder transfer runs the full flow:
///
///     transfer()
///        → not paused, neither wallet frozen, enough UNFROZEN balance
///        → identityRegistry.isVerified(to)        (identity + claim checks)
///        → compliance.canTransfer(from, to, amt)  (compliance checks)
///        → _transfer(...)                         (execute)
///        → compliance.transferred(from, to, amt)  (update module state)
///
/// Agents get privileged paths (mint / burn / forcedTransfer / freeze / pause)
/// that a normal ERC-20 has no concept of — this is what "the issuer keeps
/// control after issuance" means in code.
contract Token is ERC20, Pausable, AgentRole, IToken {
    uint8 private immutable _decimals;

    IIdentityRegistry private _identityRegistry;
    ICompliance private _compliance;

    mapping(address account => bool frozen) private _frozen; // whole-wallet freeze
    mapping(address account => uint256 amount) private _frozenTokens; // partial freeze

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        IIdentityRegistry identityRegistry_,
        ICompliance compliance_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
        _identityRegistry = identityRegistry_;
        _compliance = compliance_;
        emit IdentityRegistrySet(address(identityRegistry_));
        emit ComplianceSet(address(compliance_));
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    // ===================================================================
    // Gated user transfers — the ERC-3643 transfer flow
    // ===================================================================

    function transfer(address to, uint256 amount)
        public
        override(ERC20, IERC20)
        whenNotPaused
        returns (bool)
    {
        _checkTransfer(msg.sender, to, amount);
        bool ok = super.transfer(to, amount);
        _compliance.transferred(msg.sender, to, amount);
        return ok;
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        override(ERC20, IERC20)
        whenNotPaused
        returns (bool)
    {
        _checkTransfer(from, to, amount);
        bool ok = super.transferFrom(from, to, amount); // also spends allowance
        _compliance.transferred(from, to, amount);
        return ok;
    }

    /// @dev The four gates every user transfer must pass.
    function _checkTransfer(address from, address to, uint256 amount) private view {
        require(!_frozen[from], "Token: sender wallet frozen");
        require(!_frozen[to], "Token: recipient wallet frozen");
        require(amount <= balanceOf(from) - _frozenTokens[from], "Token: insufficient unfrozen balance");
        require(_identityRegistry.isVerified(to), "Token: recipient identity not verified");
        require(_compliance.canTransfer(from, to, amount), "Token: transfer breaks compliance");
    }

    // ===================================================================
    // Agent: supply
    // ===================================================================

    function mint(address to, uint256 amount) public override onlyAgent {
        require(_identityRegistry.isVerified(to), "Token: recipient identity not verified");
        _mint(to, amount);
        _compliance.created(to, amount);
    }

    function burn(address from, uint256 amount) public override onlyAgent {
        require(balanceOf(from) >= amount, "Token: burn exceeds balance");
        // burning eats into frozen tokens if needed
        uint256 free = balanceOf(from) - _frozenTokens[from];
        if (amount > free) {
            uint256 toUnfreeze = amount - free;
            _frozenTokens[from] -= toUnfreeze;
            emit TokensUnfrozen(from, toUnfreeze);
        }
        _burn(from, amount);
        _compliance.destroyed(from, amount);
    }

    // ===================================================================
    // Agent: enforcement
    // ===================================================================

    /// @notice Move tokens regardless of compliance/pause/wallet-freeze (e.g.
    ///         court order, recovery). Still requires the recipient to be a
    ///         verified identity, and can pull from frozen balance.
    function forcedTransfer(address from, address to, uint256 amount)
        public
        override
        onlyAgent
        returns (bool)
    {
        require(balanceOf(from) >= amount, "Token: transfer exceeds balance");
        require(_identityRegistry.isVerified(to), "Token: recipient identity not verified");
        uint256 free = balanceOf(from) - _frozenTokens[from];
        if (amount > free) {
            uint256 toUnfreeze = amount - free;
            _frozenTokens[from] -= toUnfreeze;
            emit TokensUnfrozen(from, toUnfreeze);
        }
        _update(from, to, amount); // bypasses the user gates on purpose
        _compliance.transferred(from, to, amount);
        return true;
    }

    function setAddressFrozen(address account, bool frozen) public override onlyAgent {
        _frozen[account] = frozen;
        emit AddressFrozen(account, frozen, msg.sender);
    }

    function freezePartialTokens(address account, uint256 amount) public override onlyAgent {
        require(balanceOf(account) >= _frozenTokens[account] + amount, "Token: freeze exceeds balance");
        _frozenTokens[account] += amount;
        emit TokensFrozen(account, amount);
    }

    function unfreezePartialTokens(address account, uint256 amount) public override onlyAgent {
        require(_frozenTokens[account] >= amount, "Token: unfreeze exceeds frozen");
        _frozenTokens[account] -= amount;
        emit TokensUnfrozen(account, amount);
    }

    function pause() external override onlyAgent {
        _pause();
    }

    function unpause() external override onlyAgent {
        _unpause();
    }

    // ===================================================================
    // Owner: wiring
    // ===================================================================

    function setIdentityRegistry(IIdentityRegistry identityRegistry_) external override onlyOwner {
        _identityRegistry = identityRegistry_;
        emit IdentityRegistrySet(address(identityRegistry_));
    }

    function setCompliance(ICompliance compliance_) external override onlyOwner {
        _compliance = compliance_;
        emit ComplianceSet(address(compliance_));
    }

    // ===================================================================
    // Views
    // ===================================================================

    function identityRegistry() external view override returns (IIdentityRegistry) {
        return _identityRegistry;
    }

    function compliance() external view override returns (ICompliance) {
        return _compliance;
    }

    function isFrozen(address account) external view override returns (bool) {
        return _frozen[account];
    }

    function getFrozenTokens(address account) external view override returns (uint256) {
        return _frozenTokens[account];
    }
}
