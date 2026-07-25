// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IClaimIssuer} from "../../phase3/interfaces/IClaimIssuer.sol";

/// @title ITrustedIssuersRegistry — which issuers are trusted, for which topics.
/// @notice Phase 3 proved a claim's signature is genuine. But genuine isn't
///         enough — a "Random MetaMask wallet" can also produce a genuine
///         signature. This registry is the allow-list of issuers the token
///         actually trusts (e.g. Deloitte, Chainalysis), scoped per topic:
///         an issuer trusted for KYC is not automatically trusted for Country.
interface ITrustedIssuersRegistry {
    event TrustedIssuerAdded(IClaimIssuer indexed issuer, uint256[] claimTopics);
    event TrustedIssuerRemoved(IClaimIssuer indexed issuer);
    event ClaimTopicsUpdated(IClaimIssuer indexed issuer, uint256[] claimTopics);

    function addTrustedIssuer(IClaimIssuer issuer, uint256[] calldata claimTopics) external;

    function removeTrustedIssuer(IClaimIssuer issuer) external;

    function updateIssuerClaimTopics(IClaimIssuer issuer, uint256[] calldata claimTopics) external;

    function getTrustedIssuers() external view returns (IClaimIssuer[] memory);

    function getTrustedIssuersForClaimTopic(uint256 claimTopic) external view returns (IClaimIssuer[] memory);

    /// @notice The Phase 4 deliverable.
    function isTrustedIssuer(address issuer) external view returns (bool);

    function getTrustedIssuerClaimTopics(IClaimIssuer issuer) external view returns (uint256[] memory);

    function hasClaimTopic(address issuer, uint256 claimTopic) external view returns (bool);
}
