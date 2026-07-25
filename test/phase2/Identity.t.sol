// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Identity} from "../../src/phase2/Identity.sol";
import {IERC734} from "../../src/phase2/interfaces/IERC734.sol";
import {IERC735} from "../../src/phase2/interfaces/IERC735.sol";

contract IdentityTest is Test {
    Identity internal id;

    address internal manager = makeAddr("manager");
    address internal walletB = makeAddr("walletB"); // second wallet for same person
    address internal claimSigner = makeAddr("claimSigner");
    address internal stranger = makeAddr("stranger");
    address internal kycIssuer = makeAddr("kycIssuer");

    // Cached from the contract in setUp (single source of truth). We cache
    // rather than call id.X() inside tests because those are external calls
    // that would consume an active vm.prank.
    uint256 internal MANAGEMENT;
    uint256 internal ACTION;
    uint256 internal CLAIM;
    uint256 internal ECDSA;

    uint256 internal constant KYC_TOPIC = 1;

    function setUp() public {
        id = new Identity(manager);
        MANAGEMENT = id.MANAGEMENT_KEY();
        ACTION = id.ACTION_KEY();
        CLAIM = id.CLAIM_SIGNER_KEY();
        ECDSA = id.KEY_TYPE_ECDSA();
    }

    /// @dev Local pure copy of Identity.keyForAddress — safe to call inside prank.
    function _k(address a) internal pure returns (bytes32) {
        return keccak256(abi.encode(a));
    }

    // --- constructor / key basics --------------------------------------

    function test_constructor_setsInitialManagementKey() public view {
        bytes32 k = _k(manager);
        assertTrue(id.keyHasPurpose(k, MANAGEMENT));

        (uint256[] memory purposes, uint256 keyType, bytes32 key) = id.getKey(k);
        assertEq(purposes.length, 1);
        assertEq(purposes[0], MANAGEMENT);
        assertEq(keyType, ECDSA);
        assertEq(key, k);

        bytes32[] memory mgmt = id.getKeysByPurpose(MANAGEMENT);
        assertEq(mgmt.length, 1);
        assertEq(mgmt[0], k);
    }

    function test_managementKeyImpliesEveryPurpose() public view {
        // A management key satisfies keyHasPurpose for any purpose.
        bytes32 k = _k(manager);
        assertTrue(id.keyHasPurpose(k, ACTION));
        assertTrue(id.keyHasPurpose(k, CLAIM));
    }

    // --- addKey ---------------------------------------------------------

    function test_addKey_bindsSecondWalletToSameIdentity() public {
        // The Phase 2 idea: one identity, many wallets.
        bytes32 kB = _k(walletB);

        vm.expectEmit(true, true, true, true);
        emit IERC734.KeyAdded(kB, ACTION, ECDSA);
        vm.prank(manager);
        id.addKey(kB, ACTION, ECDSA);

        assertTrue(id.keyHasPurpose(kB, ACTION));
        assertFalse(id.keyHasPurpose(kB, MANAGEMENT));
    }

    function test_addKey_appendsPurposeToExistingKey() public {
        bytes32 kB = _k(walletB);
        vm.startPrank(manager);
        id.addKey(kB, ACTION, ECDSA);
        id.addKey(kB, CLAIM, ECDSA);
        vm.stopPrank();

        uint256[] memory purposes = id.getKeyPurposes(kB);
        assertEq(purposes.length, 2);
        assertTrue(id.keyHasPurpose(kB, ACTION));
        assertTrue(id.keyHasPurpose(kB, CLAIM));
    }

    function test_addKey_revertsOnDuplicatePurpose() public {
        bytes32 kB = _k(walletB);
        vm.startPrank(manager);
        id.addKey(kB, ACTION, ECDSA);
        vm.expectRevert("Identity: key already has this purpose");
        id.addKey(kB, ACTION, ECDSA);
        vm.stopPrank();
    }

    function test_addKey_revertsForNonManager() public {
        bytes32 kB = _k(walletB);
        vm.prank(stranger);
        vm.expectRevert("Identity: sender lacks a MANAGEMENT key");
        id.addKey(kB, ACTION, ECDSA);
    }

    // --- removeKey ------------------------------------------------------

    function test_removeKey_deletesKeyWhenNoPurposesLeft() public {
        bytes32 kB = _k(walletB);
        vm.startPrank(manager);
        id.addKey(kB, ACTION, ECDSA);
        id.removeKey(kB, ACTION);
        vm.stopPrank();

        assertFalse(id.keyHasPurpose(kB, ACTION));
        (,, bytes32 key) = id.getKey(kB);
        assertEq(key, bytes32(0)); // fully deleted
        assertEq(id.getKeysByPurpose(ACTION).length, 0);
    }

    function test_removeKey_keepsKeyWhenOtherPurposesRemain() public {
        bytes32 kB = _k(walletB);
        vm.startPrank(manager);
        id.addKey(kB, ACTION, ECDSA);
        id.addKey(kB, CLAIM, ECDSA);
        id.removeKey(kB, ACTION);
        vm.stopPrank();

        assertFalse(id.keyHasPurpose(kB, ACTION));
        assertTrue(id.keyHasPurpose(kB, CLAIM));
    }

    function test_removeKey_cannotRemoveLastManagementKey() public {
        bytes32 kM = _k(manager);
        vm.prank(manager);
        vm.expectRevert("Identity: cannot remove last MANAGEMENT key");
        id.removeKey(kM, MANAGEMENT);
    }

    function test_removeKey_canRemoveManagerOnceASecondExists() public {
        bytes32 kM = _k(manager);
        bytes32 kB = _k(walletB);
        vm.startPrank(manager);
        id.addKey(kB, MANAGEMENT, ECDSA);
        id.removeKey(kM, MANAGEMENT); // now allowed: two managers existed
        vm.stopPrank();

        assertFalse(id.keyHasPurpose(kM, MANAGEMENT));
        assertTrue(id.keyHasPurpose(kB, MANAGEMENT));
    }

    // --- addClaim / removeClaim ----------------------------------------

    function test_addClaim_byManager_storesClaim() public {
        // Management key implicitly has CLAIM purpose, so manager can attach.
        bytes memory sig = hex"1234";
        bytes memory data = abi.encode("KYC passed");
        bytes32 expectedId = keccak256(abi.encode(kycIssuer, KYC_TOPIC));

        vm.expectEmit(true, true, true, true);
        emit IERC735.ClaimAdded(expectedId, KYC_TOPIC, 1, kycIssuer, sig, data, "https://kyc/1");
        vm.prank(manager);
        bytes32 claimId = id.addClaim(KYC_TOPIC, 1, kycIssuer, sig, data, "https://kyc/1");
        assertEq(claimId, expectedId);

        (
            uint256 topic,
            uint256 scheme,
            address issuer,
            bytes memory signature,
            bytes memory outData,
            string memory uri
        ) = id.getClaim(claimId);
        assertEq(topic, KYC_TOPIC);
        assertEq(scheme, 1);
        assertEq(issuer, kycIssuer);
        assertEq(signature, sig);
        assertEq(outData, data);
        assertEq(uri, "https://kyc/1");

        bytes32[] memory byTopic = id.getClaimIdsByTopic(KYC_TOPIC);
        assertEq(byTopic.length, 1);
        assertEq(byTopic[0], claimId);
    }

    function test_addClaim_byDedicatedClaimKey() public {
        bytes32 kSigner = _k(claimSigner);
        vm.prank(manager);
        id.addKey(kSigner, CLAIM, ECDSA);

        vm.prank(claimSigner);
        bytes32 claimId = id.addClaim(KYC_TOPIC, 1, kycIssuer, hex"aa", "", "");
        (,, address issuer,,,) = id.getClaim(claimId);
        assertEq(issuer, kycIssuer);
    }

    function test_addClaim_revertsForNonClaimKey() public {
        vm.prank(stranger);
        vm.expectRevert("Identity: sender lacks a CLAIM key");
        id.addClaim(KYC_TOPIC, 1, kycIssuer, hex"aa", "", "");
    }

    function test_addClaim_updateSameIssuerTopic_doesNotDuplicate() public {
        vm.startPrank(manager);
        bytes32 id1 = id.addClaim(KYC_TOPIC, 1, kycIssuer, hex"aa", "v1", "");
        bytes32 id2 = id.addClaim(KYC_TOPIC, 1, kycIssuer, hex"bb", "v2", ""); // same issuer+topic
        vm.stopPrank();

        assertEq(id1, id2); // same claimId
        assertEq(id.getClaimIdsByTopic(KYC_TOPIC).length, 1); // not duplicated
        (,,, bytes memory sig, bytes memory data,) = id.getClaim(id1);
        assertEq(sig, hex"bb");
        assertEq(data, bytes("v2"));
    }

    function test_removeClaim_deletesClaim() public {
        vm.startPrank(manager);
        bytes32 claimId = id.addClaim(KYC_TOPIC, 1, kycIssuer, hex"aa", "", "");
        id.removeClaim(claimId);
        vm.stopPrank();

        (,, address issuer,,,) = id.getClaim(claimId);
        assertEq(issuer, address(0));
        assertEq(id.getClaimIdsByTopic(KYC_TOPIC).length, 0);
    }

    function test_removeClaim_revertsWhenMissing() public {
        vm.prank(manager);
        vm.expectRevert("Identity: claim does not exist");
        id.removeClaim(keccak256("nope"));
    }
}
