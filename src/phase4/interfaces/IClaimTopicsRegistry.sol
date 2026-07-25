// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IClaimTopicsRegistry — the topics an investor MUST have to hold the token.
/// @notice E.g. "to hold this security you must have a KYC claim and a Country
///         claim". The token (Phase 7) reads this list and, for each topic,
///         demands a valid claim from a trusted issuer.
interface IClaimTopicsRegistry {
    event ClaimTopicAdded(uint256 indexed claimTopic);
    event ClaimTopicRemoved(uint256 indexed claimTopic);

    function addClaimTopic(uint256 claimTopic) external;

    function removeClaimTopic(uint256 claimTopic) external;

    function getClaimTopics() external view returns (uint256[] memory);
}
