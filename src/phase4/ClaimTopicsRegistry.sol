// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IClaimTopicsRegistry} from "./interfaces/IClaimTopicsRegistry.sol";

/// @title ClaimTopicsRegistry — the required-claims list for a token.
/// @notice Owner (the token issuer) decides which claim topics are mandatory.
contract ClaimTopicsRegistry is IClaimTopicsRegistry, Ownable {
    /// @dev Matches T-REX: a token cannot require an unbounded number of
    ///      topics (every transfer would loop over all of them).
    uint256 public constant MAX_CLAIM_TOPICS = 15;

    uint256[] private _claimTopics;

    constructor() Ownable(msg.sender) {}

    function addClaimTopic(uint256 claimTopic) external override onlyOwner {
        require(_claimTopics.length < MAX_CLAIM_TOPICS, "CTR: too many topics");
        for (uint256 i = 0; i < _claimTopics.length; i++) {
            require(_claimTopics[i] != claimTopic, "CTR: topic already exists");
        }
        _claimTopics.push(claimTopic);
        emit ClaimTopicAdded(claimTopic);
    }

    function removeClaimTopic(uint256 claimTopic) external override onlyOwner {
        for (uint256 i = 0; i < _claimTopics.length; i++) {
            if (_claimTopics[i] == claimTopic) {
                _claimTopics[i] = _claimTopics[_claimTopics.length - 1];
                _claimTopics.pop();
                emit ClaimTopicRemoved(claimTopic);
                return;
            }
        }
        revert("CTR: topic does not exist");
    }

    function getClaimTopics() external view override returns (uint256[] memory) {
        return _claimTopics;
    }
}
