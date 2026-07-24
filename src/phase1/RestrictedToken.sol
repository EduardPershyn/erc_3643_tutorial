// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title RestrictedToken — the smallest possible "security token".
/// @notice Phase 1 demonstrator: it answers the three Phase 1 questions in code.
///
/// It deliberately hard-codes, in one contract, ideas that the real ERC-3643
/// splits across several contracts. Every crude piece here is a placeholder
/// for something you will build properly in a later phase:
///
///   crude here                 ->  real ERC-3643 (phase)
///   -----------------------------------------------------------
///   `_verified` mapping        ->  Identity Registry        (Phase 5)
///   the check inside _update   ->  Compliance.canTransfer   (Phase 6)
///   `agent` address            ->  Agent role               (token mgmt)
///   `recover()`                ->  ONCHAINID-based recovery (Phase 8)
///
/// The goal is NOT good design — it is to make the restriction visible.
contract RestrictedToken is ERC20 {
    /// @notice The party allowed to verify holders, freeze, mint and recover.
    ///         Stands in for the "Agent" role in real ERC-3643.
    address public agent;

    /// @notice Crude stand-in for the Identity Registry: is this wallet a
    ///         known, verified holder? In ERC-3643 this becomes a lookup of
    ///         the wallet's ONCHAINID plus its KYC claim from a trusted issuer.
    mapping(address account => bool) private _verified;

    /// @notice Crude stand-in for a compliance freeze / sanctions hit.
    mapping(address account => bool) private _frozen;

    event Verified(address indexed account);
    event Unverified(address indexed account);
    event Frozen(address indexed account);
    event Unfrozen(address indexed account);
    event Recovered(address indexed oldWallet, address indexed newWallet);

    error NotAgent(address caller);
    error NotVerified(address account);
    error AccountFrozen(address account);

    modifier onlyAgent() {
        if (msg.sender != agent) revert NotAgent(msg.sender);
        _;
    }

    constructor() ERC20("Restricted Token", "REST") {
        agent = msg.sender;
    }

    // --- Agent controls (the "who is allowed" side) ---------------------

    function setVerified(address account, bool ok) external onlyAgent {
        _verified[account] = ok;
        emit Verified(account); // (emits Verified regardless; kept minimal for Phase 1)
        if (!ok) emit Unverified(account);
    }

    function setFrozen(address account, bool frozen) external onlyAgent {
        _frozen[account] = frozen;
        emit Frozen(account);
        if (!frozen) emit Unfrozen(account);
    }

    function mint(address to, uint256 amount) external onlyAgent {
        _mint(to, amount);
    }

    function isVerified(address account) external view returns (bool) {
        return _verified[account];
    }

    function isFrozen(address account) external view returns (bool) {
        return _frozen[account];
    }

    // --- Wallet recovery (why wallet != identity) -----------------------

    /// @notice Move an entire balance and verification status from a lost
    ///         wallet to a new one. In real ERC-3643 this is authorised by
    ///         the holder's ONCHAINID, not by a privileged address — but the
    ///         idea is the same: the *identity* owns the tokens, the wallet is
    ///         just an access key that can be rotated.
    function recover(address oldWallet, address newWallet) external onlyAgent {
        uint256 bal = balanceOf(oldWallet);
        _verified[newWallet] = true;
        if (bal > 0) {
            // bypasses the transfer check by design: recovery is an agent action
            _update(oldWallet, newWallet, bal);
        }
        emit Recovered(oldWallet, newWallet);
    }

    // --- The restriction itself -----------------------------------------

    /// @dev OpenZeppelin v5 routes every mint, burn and transfer through
    ///      `_update`. That makes it the single choke point where a security
    ///      token enforces its rules — the seed of the Phase 6 compliance flow:
    ///          transfer -> identity lookup -> claim checks -> compliance -> execute
    function _update(address from, address to, uint256 value) internal override {
        // Mint (from == 0) and burn (to == 0) skip holder checks here; only
        // holder-to-holder transfers are gated in this minimal version.
        if (from != address(0) && to != address(0)) {
            if (_frozen[from]) revert AccountFrozen(from);
            if (_frozen[to]) revert AccountFrozen(to);
            if (!_verified[from]) revert NotVerified(from);
            if (!_verified[to]) revert NotVerified(to);
        }
        super._update(from, to, value);
    }
}
