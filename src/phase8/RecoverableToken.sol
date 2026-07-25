// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Token} from "../phase7/Token.sol";
import {IIdentity} from "../phase2/interfaces/IIdentity.sol";
import {IIdentityRegistry} from "../phase5/interfaces/IIdentityRegistry.sol";
import {ICompliance} from "../phase6/interfaces/ICompliance.sol";

/// @title RecoverableToken — Phase 7 token + wallet recovery.
/// @notice Institutions cannot use a token where a lost private key = lost
///         assets forever. ERC-3643 solves this because the ONCHAINID owns the
///         position; a wallet is just a key that can be rotated.
///
///     Old Wallet ─┐
///                 ├─► ONCHAINID (holds the KYC claims)
///     New Wallet ─┘
///
/// Recovery is composed entirely from Phase 7 primitives — `forcedTransfer`
/// (to move even frozen tokens) plus the ERC-734 key check — so it needed no
/// changes to the base token. In production T-REX this lives directly in Token.
contract RecoverableToken is Token {
    /// @dev ERC-734 MANAGEMENT purpose. The new wallet must hold this on the
    ///      investor's identity — that is the proof it is the same person.
    uint256 private constant MANAGEMENT_KEY = 1;

    event WalletRecovered(address indexed oldWallet, address indexed newWallet, address indexed identity);

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        IIdentityRegistry identityRegistry_,
        ICompliance compliance_
    ) Token(name_, symbol_, decimals_, identityRegistry_, compliance_) {}

    /// @notice Move an investor's entire position from a lost wallet to a new
    ///         one that belongs to the same ONCHAINID.
    /// @dev Requires: this token is an agent on the identity registry (to
    ///      re-register), and caller is a token agent. The new wallet must
    ///      already be a MANAGEMENT key on the investor's identity.
    function recoverWallet(address oldWallet, address newWallet) external onlyAgent returns (bool) {
        uint256 balance = balanceOf(oldWallet);
        require(balance > 0, "Recovery: nothing to recover");

        IIdentityRegistry registry = this.identityRegistry();
        IIdentity investorId = registry.identity(oldWallet);
        require(address(investorId) != address(0), "Recovery: old wallet not registered");

        // The heart of recovery: the new wallet must prove it belongs to the
        // same identity by being a management key on it.
        require(
            investorId.keyHasPurpose(keccak256(abi.encode(newWallet)), MANAGEMENT_KEY),
            "Recovery: new wallet is not a management key on the identity"
        );

        // snapshot freeze state before moving anything
        uint16 country = registry.investorCountry(oldWallet);
        uint256 frozenAmount = this.getFrozenTokens(oldWallet);
        bool wasWalletFrozen = this.isFrozen(oldWallet);

        // 1. link the new wallet to the SAME identity (so it is verified)
        registry.registerIdentity(newWallet, investorId, country);

        // 2. move the whole balance, including frozen tokens (forcedTransfer)
        forcedTransfer(oldWallet, newWallet, balance);

        // 3. re-apply the freeze state to the new wallet
        if (frozenAmount > 0) {
            freezePartialTokens(newWallet, frozenAmount);
        }
        if (wasWalletFrozen) {
            setAddressFrozen(newWallet, true);
        }

        // 4. retire the lost wallet
        registry.deleteIdentity(oldWallet);

        emit WalletRecovered(oldWallet, newWallet, address(investorId));
        return true;
    }
}
