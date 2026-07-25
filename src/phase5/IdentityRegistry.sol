// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AgentRole} from "../common/AgentRole.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";
import {IIdentity} from "../phase2/interfaces/IIdentity.sol";
import {IClaimTopicsRegistry} from "../phase4/interfaces/IClaimTopicsRegistry.sol";
import {ITrustedIssuersRegistry} from "../phase4/interfaces/ITrustedIssuersRegistry.sol";
import {IClaimIssuer} from "../phase3/interfaces/IClaimIssuer.sol";

/// @title IdentityRegistry — wallet -> ONCHAINID, plus on-chain verification.
/// @notice Agents register/remove/update the wallet->identity mapping (the
///         Phase 5 deliverable). `isVerified` then combines the Phase 4
///         registries with the Phase 2/3 claims to decide if a wallet is
///         eligible to hold the token.
contract IdentityRegistry is IIdentityRegistry, AgentRole {
    struct Investor {
        IIdentity identity;
        uint16 country;
    }

    mapping(address wallet => Investor) private _investors;

    IClaimTopicsRegistry public topicsRegistry;
    ITrustedIssuersRegistry public issuersRegistry;

    constructor(IClaimTopicsRegistry _topicsRegistry, ITrustedIssuersRegistry _issuersRegistry) {
        topicsRegistry = _topicsRegistry;
        issuersRegistry = _issuersRegistry;
    }

    // --- registry mutations (agents) -----------------------------------

    function registerIdentity(address wallet, IIdentity identity_, uint16 country)
        external
        override
        onlyAgent
    {
        require(wallet != address(0), "IR: zero wallet");
        require(address(identity_) != address(0), "IR: zero identity");
        require(address(_investors[wallet].identity) == address(0), "IR: already registered");

        _investors[wallet] = Investor({identity: identity_, country: country});
        emit IdentityRegistered(wallet, identity_);
    }

    function deleteIdentity(address wallet) external override onlyAgent {
        IIdentity id = _investors[wallet].identity;
        require(address(id) != address(0), "IR: not registered");
        delete _investors[wallet];
        emit IdentityRemoved(wallet, id);
    }

    function updateIdentity(address wallet, IIdentity newIdentity) external override onlyAgent {
        IIdentity old = _investors[wallet].identity;
        require(address(old) != address(0), "IR: not registered");
        require(address(newIdentity) != address(0), "IR: zero identity");
        _investors[wallet].identity = newIdentity;
        emit IdentityUpdated(old, newIdentity);
    }

    function updateCountry(address wallet, uint16 country) external override onlyAgent {
        require(address(_investors[wallet].identity) != address(0), "IR: not registered");
        _investors[wallet].country = country;
        emit CountryUpdated(wallet, country);
    }

    // --- lookups --------------------------------------------------------

    function contains(address wallet) external view override returns (bool) {
        return address(_investors[wallet].identity) != address(0);
    }

    function identity(address wallet) external view override returns (IIdentity) {
        return _investors[wallet].identity;
    }

    function investorCountry(address wallet) external view override returns (uint16) {
        return _investors[wallet].country;
    }

    // --- verification (Phases 2 + 3 + 4 combined) ----------------------

    /// @dev For each required topic, the identity must hold at least one claim
    ///      whose issuer is trusted FOR THAT TOPIC and which the issuer confirms
    ///      is valid. Any single required topic left unsatisfied => not verified.
    function isVerified(address wallet) external view override returns (bool) {
        IIdentity id = _investors[wallet].identity;
        if (address(id) == address(0)) return false;

        uint256[] memory requiredTopics = topicsRegistry.getClaimTopics();
        if (requiredTopics.length == 0) return true; // nothing required

        for (uint256 t = 0; t < requiredTopics.length; t++) {
            if (!_hasValidClaimForTopic(id, requiredTopics[t])) return false;
        }
        return true;
    }

    function _hasValidClaimForTopic(IIdentity id, uint256 topic) private view returns (bool) {
        bytes32[] memory claimIds = id.getClaimIdsByTopic(topic);
        for (uint256 c = 0; c < claimIds.length; c++) {
            (, , address issuer, bytes memory sig, bytes memory data,) = id.getClaim(claimIds[c]);

            // Issuer must be trusted specifically for this topic.
            if (!issuersRegistry.hasClaimTopic(issuer, topic)) continue;

            // Ask the issuer contract whether the claim is genuine & unrevoked.
            // try/catch: a claim stored with a non-IClaimIssuer address (e.g. an
            // EOA) must be ignored, not revert the whole verification.
            try IClaimIssuer(issuer).isClaimValid(address(id), topic, sig, data) returns (bool valid) {
                if (valid) return true;
            } catch {
                continue;
            }
        }
        return false;
    }

    // --- admin ----------------------------------------------------------

    function setTopicsRegistry(IClaimTopicsRegistry _topicsRegistry) external onlyOwner {
        topicsRegistry = _topicsRegistry;
    }

    function setIssuersRegistry(ITrustedIssuersRegistry _issuersRegistry) external onlyOwner {
        issuersRegistry = _issuersRegistry;
    }
}
