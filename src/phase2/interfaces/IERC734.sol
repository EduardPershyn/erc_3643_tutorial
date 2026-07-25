// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IERC734 — "Key Manager" (simplified).
/// @notice Key management half of an ONCHAINID identity. Keys are stored as
///         bytes32 = keccak256(abi.encode(walletAddress)), so ONE identity can
///         be controlled by MANY wallets — the core Phase 2 idea:
///
///             Person -> Wallet A / Wallet B / Wallet C -> one ONCHAINID
///
///         Purposes:
///           1 MANAGEMENT — can add/remove keys and claims (the "admin" key)
///           2 ACTION     — can act on behalf of the identity
///           3 CLAIM      — a claim signer; may attach claims to this identity
///           4 ENCRYPTION — holds an encryption key (data only)
///
///         Key types: 1 = ECDSA, 2 = RSA.
///
/// @dev The ERC-734 execute()/approve() transaction-execution model is
///      intentionally omitted here — not needed for the Phase 2 deliverable.
interface IERC734 {
    event KeyAdded(bytes32 indexed key, uint256 indexed purpose, uint256 indexed keyType);
    event KeyRemoved(bytes32 indexed key, uint256 indexed purpose, uint256 indexed keyType);

    function addKey(bytes32 _key, uint256 _purpose, uint256 _keyType) external returns (bool success);

    function removeKey(bytes32 _key, uint256 _purpose) external returns (bool success);

    function getKey(bytes32 _key)
        external
        view
        returns (uint256[] memory purposes, uint256 keyType, bytes32 key);

    function getKeyPurposes(bytes32 _key) external view returns (uint256[] memory purposes);

    function getKeysByPurpose(uint256 _purpose) external view returns (bytes32[] memory keys);

    function keyHasPurpose(bytes32 _key, uint256 _purpose) external view returns (bool exists);
}
