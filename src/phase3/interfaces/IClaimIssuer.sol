// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IClaimIssuer — a contract that issues and can revoke claims.
/// @notice This is what Phase 2 was missing: a way to VERIFY a stored claim.
///
/// The issuer signs a claim off-chain over (identity, topic, data). Anyone can
/// later ask this contract "is this signature a genuine, still-valid claim?"
/// via `isClaimValid`. The issuer can also revoke a specific claim signature.
///
/// In ERC-3643 the claim's `issuer` field points at a ClaimIssuer *contract*
/// (not an EOA) precisely so that verification and revocation are queryable
/// on-chain by the token / identity registry.
interface IClaimIssuer {
    event ClaimRevoked(bytes indexed signature);

    /// @notice Permanently revoke one claim, identified by its signature.
    function revokeClaimBySignature(bytes calldata signature) external;

    /// @notice Has this exact claim signature been revoked?
    function isClaimRevoked(bytes calldata signature) external view returns (bool);

    /// @notice True iff `signature` is a genuine, non-revoked claim by this
    ///         issuer that `identity` holds topic `claimTopic` with `data`.
    /// @dev    Recovers the signer from an eth_sign signature over
    ///         keccak256(abi.encode(identity, claimTopic, data)) and checks the
    ///         signer holds a CLAIM key (purpose 3) on this issuer.
    function isClaimValid(address identity, uint256 claimTopic, bytes calldata signature, bytes calldata data)
        external
        view
        returns (bool);
}
