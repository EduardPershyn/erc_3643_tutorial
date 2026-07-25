// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Identity} from "../phase2/Identity.sol";
import {IClaimIssuer} from "./interfaces/IClaimIssuer.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title ClaimIssuer — an Identity that can sign, verify and revoke claims.
/// @notice Phase 3: a trusted issuer (e.g. a KYC provider). It IS an ONCHAINID
///         (so it holds keys), plus:
///           - isClaimValid: verify an off-chain signature on-chain
///           - revokeClaimBySignature / isClaimRevoked: kill a claim
///
/// A KYC provider deploys one of these. Its signing wallet is a CLAIM key
/// (purpose 3) on the issuer. It signs each investor's claim off-chain; the
/// investor stores that claim on their own Identity (Phase 2); later the token
/// asks THIS contract whether the claim is genuine and still valid.
contract ClaimIssuer is Identity, IClaimIssuer {
    mapping(bytes32 sigHash => bool revoked) private _revoked;

    constructor(address initialManagementKey) Identity(initialManagementKey) {}

    function revokeClaimBySignature(bytes calldata signature) external override onlyManager {
        _revoked[keccak256(signature)] = true;
        emit ClaimRevoked(signature);
    }

    function isClaimRevoked(bytes calldata signature) public view override returns (bool) {
        return _revoked[keccak256(signature)];
    }

    function isClaimValid(address identity, uint256 claimTopic, bytes calldata signature, bytes calldata data)
        public
        view
        override
        returns (bool)
    {
        if (_revoked[keccak256(signature)]) return false;

        // Reconstruct exactly what the issuer signed off-chain.
        bytes32 dataHash = keccak256(abi.encode(identity, claimTopic, data));
        bytes32 prefixedHash = MessageHashUtils.toEthSignedMessageHash(dataHash);

        // tryRecover returns an error (not a revert) on malformed signatures.
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(prefixedHash, signature);
        if (err != ECDSA.RecoverError.NoError) return false;

        // The recovered wallet must be a CLAIM key on this issuer.
        // (A MANAGEMENT key implicitly satisfies CLAIM — see Identity.)
        return keyHasPurpose(keccak256(abi.encode(signer)), CLAIM_SIGNER_KEY);
    }
}
