// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IIdentity} from "../../phase2/interfaces/IIdentity.sol";

/// @title IIdentityRegistry — maps wallets to ONCHAINIDs and answers "verified?".
/// @notice
///     Wallet  ->  Identity Registry  ->  ONCHAINID
///     0xAAA   ->                     ->  Identity #1
///     0xBBB   ->                     ->  Identity #2
///
/// It also carries each investor's country and, crucially, `isVerified` — the
/// claim check the token runs on every transfer (combines Phases 2/3/4).
interface IIdentityRegistry {
    event IdentityRegistered(address indexed wallet, IIdentity indexed identity);
    event IdentityRemoved(address indexed wallet, IIdentity indexed identity);
    event IdentityUpdated(IIdentity indexed oldIdentity, IIdentity indexed newIdentity);
    event CountryUpdated(address indexed wallet, uint16 indexed country);

    // --- deliverable ---
    function registerIdentity(address wallet, IIdentity identity, uint16 country) external;
    function deleteIdentity(address wallet) external;
    function contains(address wallet) external view returns (bool);

    // --- supporting lookups ---
    function updateIdentity(address wallet, IIdentity newIdentity) external;
    function updateCountry(address wallet, uint16 country) external;
    function identity(address wallet) external view returns (IIdentity);
    function investorCountry(address wallet) external view returns (uint16);

    /// @notice Is `wallet` registered AND does its identity hold a valid claim
    ///         (from a trusted issuer) for every required topic?
    function isVerified(address wallet) external view returns (bool);
}
