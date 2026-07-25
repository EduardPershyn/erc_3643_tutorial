// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../../src/phase5/IdentityRegistry.sol";
import {IIdentity} from "../../src/phase2/interfaces/IIdentity.sol";
import {Identity} from "../../src/phase2/Identity.sol";
import {ClaimIssuer} from "../../src/phase3/ClaimIssuer.sol";
import {Topics} from "../../src/phase3/Topics.sol";
import {ClaimTopicsRegistry} from "../../src/phase4/ClaimTopicsRegistry.sol";
import {TrustedIssuersRegistry} from "../../src/phase4/TrustedIssuersRegistry.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract IdentityRegistryTest is Test {
    IdentityRegistry internal ir;
    ClaimTopicsRegistry internal topics;
    TrustedIssuersRegistry internal tir;

    ClaimIssuer internal kycIssuer;
    address internal claimSigner;
    uint256 internal claimSignerPk;

    address internal agent = makeAddr("agent");
    address internal aliceWallet = makeAddr("aliceWallet");
    address internal bobWallet = makeAddr("bobWallet");

    Identity internal aliceId;

    uint16 internal constant US = 840;
    uint16 internal constant FRANCE = 250;
    bytes internal constant KYC_DATA = abi.encode("KYC:PASS");

    function setUp() public {
        (claimSigner, claimSignerPk) = makeAddrAndKey("claimSigner");

        topics = new ClaimTopicsRegistry();
        tir = new TrustedIssuersRegistry();
        ir = new IdentityRegistry(topics, tir);
        ir.addAgent(agent); // owner (this contract) appoints the agent

        // A trusted KYC issuer with a dedicated claim signer.
        kycIssuer = new ClaimIssuer(makeAddr("kycAdmin"));
        // Read constants BEFORE the prank (external calls would consume it).
        uint256 claimPurpose = kycIssuer.CLAIM_SIGNER_KEY();
        uint256 ecdsaType = kycIssuer.KEY_TYPE_ECDSA();
        vm.prank(makeAddr("kycAdmin"));
        kycIssuer.addKey(keccak256(abi.encode(claimSigner)), claimPurpose, ecdsaType);

        aliceId = new Identity(aliceWallet);
    }

    // ===================================================================
    // Deliverable: registerIdentity / deleteIdentity / contains
    // ===================================================================

    function test_registerIdentity_thenContains() public {
        vm.prank(agent);
        ir.registerIdentity(aliceWallet, aliceId, US);

        assertTrue(ir.contains(aliceWallet));
        assertEq(address(ir.identity(aliceWallet)), address(aliceId));
        assertEq(ir.investorCountry(aliceWallet), US);
        assertFalse(ir.contains(bobWallet));
    }

    function test_deleteIdentity() public {
        vm.startPrank(agent);
        ir.registerIdentity(aliceWallet, aliceId, US);
        ir.deleteIdentity(aliceWallet);
        vm.stopPrank();

        assertFalse(ir.contains(aliceWallet));
        assertEq(address(ir.identity(aliceWallet)), address(0));
    }

    function test_register_revertsOnDuplicate() public {
        vm.startPrank(agent);
        ir.registerIdentity(aliceWallet, aliceId, US);
        vm.expectRevert("IR: already registered");
        ir.registerIdentity(aliceWallet, aliceId, US);
        vm.stopPrank();
    }

    function test_register_revertsOnZeroIdentity() public {
        vm.prank(agent);
        vm.expectRevert("IR: zero identity");
        ir.registerIdentity(aliceWallet, IIdentity(address(0)), US);
    }

    function test_updateIdentity_and_updateCountry() public {
        vm.startPrank(agent);
        ir.registerIdentity(aliceWallet, aliceId, US);

        Identity aliceId2 = new Identity(aliceWallet);
        ir.updateIdentity(aliceWallet, aliceId2);
        assertEq(address(ir.identity(aliceWallet)), address(aliceId2));

        ir.updateCountry(aliceWallet, FRANCE);
        assertEq(ir.investorCountry(aliceWallet), FRANCE);
        vm.stopPrank();
    }

    function test_register_onlyAgent() public {
        vm.prank(bobWallet); // not an agent
        vm.expectRevert("AgentRole: caller is not an agent");
        ir.registerIdentity(aliceWallet, aliceId, US);
    }

    // ===================================================================
    // isVerified — Phases 2 + 3 + 4 combined
    // ===================================================================

    function test_isVerified_falseWhenNotRegistered() public view {
        assertFalse(ir.isVerified(aliceWallet));
    }

    function test_isVerified_trueWhenNoTopicsRequired() public {
        // No required topics => registration alone is enough.
        vm.prank(agent);
        ir.registerIdentity(aliceWallet, aliceId, US);
        assertTrue(ir.isVerified(aliceWallet));
    }

    function test_isVerified_falseWhenRequiredClaimMissing() public {
        topics.addClaimTopic(Topics.KYC);
        tir.addTrustedIssuer(kycIssuer, _arr1(Topics.KYC));

        vm.prank(agent);
        ir.registerIdentity(aliceWallet, aliceId, US); // registered but no KYC claim
        assertFalse(ir.isVerified(aliceWallet));
    }

    function test_isVerified_trueWithValidTrustedClaim() public {
        topics.addClaimTopic(Topics.KYC);
        tir.addTrustedIssuer(kycIssuer, _arr1(Topics.KYC));
        _giveAliceKycClaim();

        vm.prank(agent);
        ir.registerIdentity(aliceWallet, aliceId, US);

        assertTrue(ir.isVerified(aliceWallet));
    }

    function test_isVerified_falseWhenIssuerNotTrusted() public {
        topics.addClaimTopic(Topics.KYC);
        // NOTE: kycIssuer is deliberately NOT added to the trusted registry.
        _giveAliceKycClaim();

        vm.prank(agent);
        ir.registerIdentity(aliceWallet, aliceId, US);

        assertFalse(ir.isVerified(aliceWallet));
    }

    function test_isVerified_falseWhenIssuerTrustedForDifferentTopic() public {
        topics.addClaimTopic(Topics.KYC);
        tir.addTrustedIssuer(kycIssuer, _arr1(Topics.AML)); // trusted for AML, not KYC
        _giveAliceKycClaim();

        vm.prank(agent);
        ir.registerIdentity(aliceWallet, aliceId, US);

        assertFalse(ir.isVerified(aliceWallet));
    }

    function test_isVerified_falseAfterClaimRevoked() public {
        topics.addClaimTopic(Topics.KYC);
        tir.addTrustedIssuer(kycIssuer, _arr1(Topics.KYC));
        bytes memory sig = _giveAliceKycClaim();

        vm.prank(agent);
        ir.registerIdentity(aliceWallet, aliceId, US);
        assertTrue(ir.isVerified(aliceWallet));

        // KYC provider revokes -> Alice no longer verified (drives Phase 10).
        vm.prank(makeAddr("kycAdmin"));
        kycIssuer.revokeClaimBySignature(sig);
        assertFalse(ir.isVerified(aliceWallet));
    }

    function test_isVerified_requiresAllTopics() public {
        topics.addClaimTopic(Topics.KYC);
        topics.addClaimTopic(Topics.COUNTRY);
        tir.addTrustedIssuer(kycIssuer, _arr2(Topics.KYC, Topics.COUNTRY));
        _giveAliceKycClaim(); // only KYC, not COUNTRY

        vm.prank(agent);
        ir.registerIdentity(aliceWallet, aliceId, US);

        // KYC satisfied but COUNTRY missing => not verified.
        assertFalse(ir.isVerified(aliceWallet));
    }

    // --- helpers --------------------------------------------------------

    /// @dev Signs and stores a valid KYC claim on Alice's identity; returns the
    ///      signature so tests can revoke it.
    function _giveAliceKycClaim() private returns (bytes memory sig) {
        bytes32 dataHash = keccak256(abi.encode(address(aliceId), Topics.KYC, KYC_DATA));
        bytes32 prefixed = MessageHashUtils.toEthSignedMessageHash(dataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimSignerPk, prefixed);
        sig = abi.encodePacked(r, s, v);

        vm.prank(aliceWallet);
        aliceId.addClaim(Topics.KYC, 1, address(kycIssuer), sig, KYC_DATA, "");
    }

    function _arr1(uint256 a) private pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = a;
    }

    function _arr2(uint256 a, uint256 b) private pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
    }
}
