// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITrustedIssuersRegistry} from "./interfaces/ITrustedIssuersRegistry.sol";
import {IClaimIssuer} from "../phase3/interfaces/IClaimIssuer.sol";

/// @title TrustedIssuersRegistry — the per-topic allow-list of claim issuers.
/// @notice Owner (the token issuer) registers each trusted ClaimIssuer with the
///         set of topics it may attest. `isTrustedIssuer` / `hasClaimTopic`
///         are the queries the token uses in Phase 7.
contract TrustedIssuersRegistry is ITrustedIssuersRegistry, Ownable {
    uint256 public constant MAX_TOPICS_PER_ISSUER = 15;

    // all trusted issuers (for enumeration)
    IClaimIssuer[] private _trustedIssuers;
    // issuer => topics it is trusted for
    mapping(address issuer => uint256[] topics) private _issuerTopics;
    // topic => issuers trusted for it (fast lookup used by the token)
    mapping(uint256 topic => IClaimIssuer[] issuers) private _issuersByTopic;

    constructor() Ownable(msg.sender) {}

    // --- mutations (owner only) ----------------------------------------

    function addTrustedIssuer(IClaimIssuer issuer, uint256[] calldata claimTopics)
        external
        override
        onlyOwner
    {
        require(address(issuer) != address(0), "TIR: zero issuer");
        require(_issuerTopics[address(issuer)].length == 0, "TIR: issuer already exists");
        require(claimTopics.length > 0, "TIR: no topics");
        require(claimTopics.length <= MAX_TOPICS_PER_ISSUER, "TIR: too many topics");
        _requireNoDuplicateTopics(claimTopics);

        _trustedIssuers.push(issuer);
        _issuerTopics[address(issuer)] = claimTopics;
        for (uint256 i = 0; i < claimTopics.length; i++) {
            _issuersByTopic[claimTopics[i]].push(issuer);
        }
        emit TrustedIssuerAdded(issuer, claimTopics);
    }

    function removeTrustedIssuer(IClaimIssuer issuer) external override onlyOwner {
        require(_issuerTopics[address(issuer)].length != 0, "TIR: issuer does not exist");

        uint256[] memory oldTopics = _issuerTopics[address(issuer)];
        for (uint256 i = 0; i < oldTopics.length; i++) {
            _removeIssuerFromArray(_issuersByTopic[oldTopics[i]], issuer);
        }
        delete _issuerTopics[address(issuer)];
        _removeIssuerFromArray(_trustedIssuers, issuer);

        emit TrustedIssuerRemoved(issuer);
    }

    function updateIssuerClaimTopics(IClaimIssuer issuer, uint256[] calldata claimTopics)
        external
        override
        onlyOwner
    {
        require(_issuerTopics[address(issuer)].length != 0, "TIR: issuer does not exist");
        require(claimTopics.length > 0, "TIR: no topics");
        require(claimTopics.length <= MAX_TOPICS_PER_ISSUER, "TIR: too many topics");
        _requireNoDuplicateTopics(claimTopics);

        // unwind old per-topic entries, then re-add the new set
        uint256[] memory oldTopics = _issuerTopics[address(issuer)];
        for (uint256 i = 0; i < oldTopics.length; i++) {
            _removeIssuerFromArray(_issuersByTopic[oldTopics[i]], issuer);
        }
        _issuerTopics[address(issuer)] = claimTopics;
        for (uint256 i = 0; i < claimTopics.length; i++) {
            _issuersByTopic[claimTopics[i]].push(issuer);
        }
        emit ClaimTopicsUpdated(issuer, claimTopics);
    }

    // --- views ----------------------------------------------------------

    function isTrustedIssuer(address issuer) external view override returns (bool) {
        return _issuerTopics[issuer].length != 0;
    }

    function getTrustedIssuers() external view override returns (IClaimIssuer[] memory) {
        return _trustedIssuers;
    }

    function getTrustedIssuersForClaimTopic(uint256 claimTopic)
        external
        view
        override
        returns (IClaimIssuer[] memory)
    {
        return _issuersByTopic[claimTopic];
    }

    function getTrustedIssuerClaimTopics(IClaimIssuer issuer)
        external
        view
        override
        returns (uint256[] memory)
    {
        require(_issuerTopics[address(issuer)].length != 0, "TIR: issuer does not exist");
        return _issuerTopics[address(issuer)];
    }

    function hasClaimTopic(address issuer, uint256 claimTopic) external view override returns (bool) {
        uint256[] memory topics = _issuerTopics[issuer];
        for (uint256 i = 0; i < topics.length; i++) {
            if (topics[i] == claimTopic) return true;
        }
        return false;
    }

    // --- internal helpers ----------------------------------------------

    function _requireNoDuplicateTopics(uint256[] calldata topics) private pure {
        for (uint256 i = 0; i < topics.length; i++) {
            for (uint256 j = i + 1; j < topics.length; j++) {
                require(topics[i] != topics[j], "TIR: duplicate topic");
            }
        }
    }

    function _removeIssuerFromArray(IClaimIssuer[] storage arr, IClaimIssuer issuer) private {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == issuer) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                return;
            }
        }
    }
}
