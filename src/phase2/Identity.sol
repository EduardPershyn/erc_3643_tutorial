// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC734} from "./interfaces/IERC734.sol";
import {IERC735} from "./interfaces/IERC735.sol";

/// @title Identity — a simplified ONCHAINID.
/// @notice Phase 2 deliverable: one on-chain identity that
///           - is controlled by keys (ERC-734), and
///           - carries claims about itself (ERC-735).
///
/// This is the real thing that replaces Phase 1's crude `_verified` mapping:
/// instead of the token storing "address => bool", each investor deploys an
/// Identity, and verification later (Phase 5) means "this wallet maps to an
/// Identity that holds a valid KYC claim from a trusted issuer".
///
/// Access model (matches ONCHAINID): a MANAGEMENT key (purpose 1) satisfies
/// `keyHasPurpose` for ANY purpose, so the manager can also add claims. A
/// dedicated CLAIM key (purpose 3) can add claims but not manage keys.
///
/// Simplifications vs. production ONCHAINID: no proxy/upgradeability, no
/// execute()/approve() transaction model, and claim signatures are stored but
/// not verified here (that is Phase 3).
contract Identity is IERC734, IERC735 {
    // --- purpose constants ---
    uint256 public constant MANAGEMENT_KEY = 1;
    uint256 public constant ACTION_KEY = 2;
    uint256 public constant CLAIM_SIGNER_KEY = 3;
    uint256 public constant ENCRYPTION_KEY = 4;

    // --- key type constants ---
    uint256 public constant KEY_TYPE_ECDSA = 1;
    uint256 public constant KEY_TYPE_RSA = 2;

    struct Key {
        uint256[] purposes;
        uint256 keyType;
        bytes32 key;
    }

    struct Claim {
        uint256 topic;
        uint256 scheme;
        address issuer;
        bytes signature;
        bytes data;
        string uri;
    }

    mapping(bytes32 keyId => Key) private _keys;
    mapping(uint256 purpose => bytes32[] keyIds) private _keysByPurpose;

    mapping(bytes32 claimId => Claim) private _claims;
    mapping(uint256 topic => bytes32[] claimIds) private _claimsByTopic;

    modifier onlyManager() {
        require(
            msg.sender == address(this) || keyHasPurpose(keyForAddress(msg.sender), MANAGEMENT_KEY),
            "Identity: sender lacks a MANAGEMENT key"
        );
        _;
    }

    modifier onlyClaimKey() {
        require(
            msg.sender == address(this) || keyHasPurpose(keyForAddress(msg.sender), CLAIM_SIGNER_KEY),
            "Identity: sender lacks a CLAIM key"
        );
        _;
    }

    /// @param initialManagementKey the wallet that becomes the first manager.
    constructor(address initialManagementKey) {
        require(initialManagementKey != address(0), "Identity: zero management key");
        bytes32 keyId = keyForAddress(initialManagementKey);
        _keys[keyId].key = keyId;
        _keys[keyId].keyType = KEY_TYPE_ECDSA;
        _keys[keyId].purposes.push(MANAGEMENT_KEY);
        _keysByPurpose[MANAGEMENT_KEY].push(keyId);
        emit KeyAdded(keyId, MANAGEMENT_KEY, KEY_TYPE_ECDSA);
    }

    /// @notice Convenience: derive the bytes32 key id used to store a wallet.
    function keyForAddress(address wallet) public pure returns (bytes32) {
        return keccak256(abi.encode(wallet));
    }

    // =====================================================================
    // ERC-734 — Key management
    // =====================================================================

    function addKey(bytes32 _key, uint256 _purpose, uint256 _keyType)
        external
        override
        onlyManager
        returns (bool)
    {
        if (_keys[_key].key == _key) {
            // key already exists: append the new purpose (no duplicates)
            uint256[] memory existing = _keys[_key].purposes;
            for (uint256 i = 0; i < existing.length; i++) {
                require(existing[i] != _purpose, "Identity: key already has this purpose");
            }
            _keys[_key].purposes.push(_purpose);
        } else {
            _keys[_key].key = _key;
            _keys[_key].keyType = _keyType;
            _keys[_key].purposes.push(_purpose);
        }
        _keysByPurpose[_purpose].push(_key);
        emit KeyAdded(_key, _purpose, _keys[_key].keyType);
        return true;
    }

    function removeKey(bytes32 _key, uint256 _purpose) external override onlyManager returns (bool) {
        require(_keys[_key].key == _key, "Identity: key does not exist");

        uint256[] storage purposes = _keys[_key].purposes;
        uint256 idx = type(uint256).max;
        for (uint256 i = 0; i < purposes.length; i++) {
            if (purposes[i] == _purpose) {
                idx = i;
                break;
            }
        }
        require(idx != type(uint256).max, "Identity: key does not have this purpose");

        // Safety guard (addition over base ERC-734): never brick the identity
        // by removing its only remaining manager.
        if (_purpose == MANAGEMENT_KEY) {
            require(_keysByPurpose[MANAGEMENT_KEY].length > 1, "Identity: cannot remove last MANAGEMENT key");
        }

        uint256 keyType = _keys[_key].keyType;

        // remove purpose from the key's purpose list (swap & pop)
        purposes[idx] = purposes[purposes.length - 1];
        purposes.pop();

        _removeFromArray(_keysByPurpose[_purpose], _key);

        if (purposes.length == 0) {
            delete _keys[_key];
        }

        emit KeyRemoved(_key, _purpose, keyType);
        return true;
    }

    function getKey(bytes32 _key)
        external
        view
        override
        returns (uint256[] memory purposes, uint256 keyType, bytes32 key)
    {
        Key storage k = _keys[_key];
        return (k.purposes, k.keyType, k.key);
    }

    function getKeyPurposes(bytes32 _key) external view override returns (uint256[] memory) {
        return _keys[_key].purposes;
    }

    function getKeysByPurpose(uint256 _purpose) external view override returns (bytes32[] memory) {
        return _keysByPurpose[_purpose];
    }

    function keyHasPurpose(bytes32 _key, uint256 _purpose) public view override returns (bool) {
        Key storage k = _keys[_key];
        if (k.key == 0) return false;
        for (uint256 i = 0; i < k.purposes.length; i++) {
            uint256 p = k.purposes[i];
            // a MANAGEMENT key implicitly satisfies every purpose
            if (p == MANAGEMENT_KEY || p == _purpose) return true;
        }
        return false;
    }

    // =====================================================================
    // ERC-735 — Claims
    // =====================================================================

    function addClaim(
        uint256 _topic,
        uint256 _scheme,
        address _issuer,
        bytes calldata _signature,
        bytes calldata _data,
        string calldata _uri
    ) external override onlyClaimKey returns (bytes32 claimRequestId) {
        require(_issuer != address(0), "Identity: zero issuer");
        bytes32 claimId = keccak256(abi.encode(_issuer, _topic));

        if (_claims[claimId].issuer != address(0)) {
            // update in place — same (issuer, topic) => same claimId
            _claims[claimId].scheme = _scheme;
            _claims[claimId].signature = _signature;
            _claims[claimId].data = _data;
            _claims[claimId].uri = _uri;
            emit ClaimChanged(claimId, _topic, _scheme, _issuer, _signature, _data, _uri);
        } else {
            _claims[claimId] =
                Claim({topic: _topic, scheme: _scheme, issuer: _issuer, signature: _signature, data: _data, uri: _uri});
            _claimsByTopic[_topic].push(claimId);
            emit ClaimAdded(claimId, _topic, _scheme, _issuer, _signature, _data, _uri);
        }
        return claimId;
    }

    function removeClaim(bytes32 _claimId) external override onlyClaimKey returns (bool) {
        Claim storage c = _claims[_claimId];
        require(c.issuer != address(0), "Identity: claim does not exist");

        emit ClaimRemoved(_claimId, c.topic, c.scheme, c.issuer, c.signature, c.data, c.uri);

        _removeFromArray(_claimsByTopic[c.topic], _claimId);
        delete _claims[_claimId];
        return true;
    }

    function getClaim(bytes32 _claimId)
        external
        view
        override
        returns (
            uint256 topic,
            uint256 scheme,
            address issuer,
            bytes memory signature,
            bytes memory data,
            string memory uri
        )
    {
        Claim storage c = _claims[_claimId];
        return (c.topic, c.scheme, c.issuer, c.signature, c.data, c.uri);
    }

    function getClaimIdsByTopic(uint256 _topic) external view override returns (bytes32[] memory) {
        return _claimsByTopic[_topic];
    }

    // =====================================================================
    // internal helpers
    // =====================================================================

    function _removeFromArray(bytes32[] storage arr, bytes32 value) private {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                return;
            }
        }
    }
}
