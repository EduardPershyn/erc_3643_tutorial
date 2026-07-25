// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IERC735 — "Claim Holder" (simplified).
/// @notice Claims half of an ONCHAINID identity. A claim is a signed
///         attestation ABOUT this identity, made by an issuer:
///
///             Claim { topic, scheme, issuer, signature, data, uri }
///
///         Example topics (see Phase 3):
///           1 KYC   2 AML   3 Country   4 Accredited investor
///
///         The signature is produced OFF-chain by the issuer over
///         (identity, topic, data). This contract only STORES claims; whether
///         a claim is actually valid (issuer trusted + signature correct) is
///         verified in Phase 3 / Phase 4. Storage id:
///
///             claimId = keccak256(abi.encode(issuer, topic))
///
///         so one issuer can hold at most one claim per topic on this identity.
interface IERC735 {
    event ClaimAdded(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );
    event ClaimRemoved(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );
    event ClaimChanged(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );

    function addClaim(
        uint256 _topic,
        uint256 _scheme,
        address _issuer,
        bytes calldata _signature,
        bytes calldata _data,
        string calldata _uri
    ) external returns (bytes32 claimRequestId);

    function removeClaim(bytes32 _claimId) external returns (bool success);

    function getClaim(bytes32 _claimId)
        external
        view
        returns (
            uint256 topic,
            uint256 scheme,
            address issuer,
            bytes memory signature,
            bytes memory data,
            string memory uri
        );

    function getClaimIdsByTopic(uint256 _topic) external view returns (bytes32[] memory claimIds);
}
