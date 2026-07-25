// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Identity} from "../../src/phase2/Identity.sol";
import {ClaimIssuer} from "../../src/phase3/ClaimIssuer.sol";
import {IClaimIssuer} from "../../src/phase3/interfaces/IClaimIssuer.sol";
import {Topics} from "../../src/phase3/Topics.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ClaimIssuerTest is Test {
    // --- actors ---
    address internal aliceWallet = makeAddr("aliceWallet");
    address internal issuerAdmin = makeAddr("issuerAdmin"); // manages the ClaimIssuer
    address internal claimSigner; // dedicated CLAIM key that signs KYC claims
    uint256 internal claimSignerPk;
    address internal impostor; // a wallet NOT registered on the issuer
    uint256 internal impostorPk;

    // --- contracts ---
    Identity internal aliceId; // Alice's ONCHAINID
    ClaimIssuer internal issuer; // the KYC provider

    // cached constants (single source of truth; read outside pranks)
    uint256 internal CLAIM;
    uint256 internal ECDSA_TYPE;

    bytes internal constant KYC_DATA = abi.encode("KYC:PASS");

    function setUp() public {
        (claimSigner, claimSignerPk) = makeAddrAndKey("claimSigner");
        (impostor, impostorPk) = makeAddrAndKey("impostor");

        // Alice deploys her identity.
        aliceId = new Identity(aliceWallet);

        // The KYC provider deploys its ClaimIssuer and registers a claim signer.
        issuer = new ClaimIssuer(issuerAdmin);
        CLAIM = issuer.CLAIM_SIGNER_KEY();
        ECDSA_TYPE = issuer.KEY_TYPE_ECDSA();

        vm.prank(issuerAdmin);
        issuer.addKey(keccak256(abi.encode(claimSigner)), CLAIM, ECDSA_TYPE);
    }

    /// @dev Produce an eth_sign signature over (identity, topic, data),
    ///      exactly what ClaimIssuer.isClaimValid reconstructs.
    function _sign(uint256 pk, address identity, uint256 topic, bytes memory data)
        internal
        pure
        returns (bytes memory)
    {
        bytes32 dataHash = keccak256(abi.encode(identity, topic, data));
        bytes32 prefixed = MessageHashUtils.toEthSignedMessageHash(dataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, prefixed);
        return abi.encodePacked(r, s, v);
    }

    // ==================================================================
    // DELIVERABLE: Alice receives a KYC claim from a trusted issuer, and it
    // verifies on-chain. This is the full end-to-end PoC.
    // ==================================================================
    function test_aliceReceivesValidKycClaim_fromTrustedIssuer() public {
        // 1. Issuer signs Alice's KYC claim OFF-CHAIN.
        bytes memory sig = _sign(claimSignerPk, address(aliceId), Topics.KYC, KYC_DATA);

        // 2. Alice stores the claim on her own identity (issuer = the contract).
        vm.prank(aliceWallet);
        bytes32 claimId = aliceId.addClaim(Topics.KYC, 1, address(issuer), sig, KYC_DATA, "");

        // 3. Anyone can now read the claim back and VERIFY it through the
        //    issuer — this is the exact path the token uses in Phase 5/7.
        (uint256 topic,, address issuerAddr, bytes memory storedSig, bytes memory storedData,) =
            aliceId.getClaim(claimId);

        assertEq(issuerAddr, address(issuer));
        assertTrue(
            IClaimIssuer(issuerAddr).isClaimValid(address(aliceId), topic, storedSig, storedData),
            "claim should be valid"
        );
    }

    // --- negative cases -------------------------------------------------

    function test_isClaimValid_falseWhenSignedByUnregisteredWallet() public view {
        // Impostor signs a claim, but is not a CLAIM key on the issuer.
        bytes memory sig = _sign(impostorPk, address(aliceId), Topics.KYC, KYC_DATA);
        assertFalse(issuer.isClaimValid(address(aliceId), Topics.KYC, sig, KYC_DATA));
    }

    function test_isClaimValid_falseWhenDataTampered() public view {
        bytes memory sig = _sign(claimSignerPk, address(aliceId), Topics.KYC, KYC_DATA);
        // Verify against different data than what was signed.
        bytes memory tampered = abi.encode("KYC:FAIL");
        assertFalse(issuer.isClaimValid(address(aliceId), Topics.KYC, sig, tampered));
    }

    function test_isClaimValid_falseForWrongTopic() public view {
        // Signed for KYC, checked as AML -> signer recovers to a different hash.
        bytes memory sig = _sign(claimSignerPk, address(aliceId), Topics.KYC, KYC_DATA);
        assertFalse(issuer.isClaimValid(address(aliceId), Topics.AML, sig, KYC_DATA));
    }

    function test_isClaimValid_falseForWrongIdentity() public {
        Identity bobId = new Identity(makeAddr("bobWallet"));
        // Claim was bound to Alice's identity; Bob can't reuse it.
        bytes memory sig = _sign(claimSignerPk, address(aliceId), Topics.KYC, KYC_DATA);
        assertFalse(issuer.isClaimValid(address(bobId), Topics.KYC, sig, KYC_DATA));
    }

    function test_isClaimValid_falseForMalformedSignature() public view {
        // Garbage signature -> tryRecover errors -> false (not a revert).
        assertFalse(issuer.isClaimValid(address(aliceId), Topics.KYC, hex"dead", KYC_DATA));
    }

    // --- revocation -----------------------------------------------------

    function test_revoke_makesValidClaimInvalid() public {
        bytes memory sig = _sign(claimSignerPk, address(aliceId), Topics.KYC, KYC_DATA);
        assertTrue(issuer.isClaimValid(address(aliceId), Topics.KYC, sig, KYC_DATA));

        vm.prank(issuerAdmin);
        issuer.revokeClaimBySignature(sig);

        assertTrue(issuer.isClaimRevoked(sig));
        assertFalse(issuer.isClaimValid(address(aliceId), Topics.KYC, sig, KYC_DATA));
    }

    function test_revoke_onlyManager() public {
        bytes memory sig = _sign(claimSignerPk, address(aliceId), Topics.KYC, KYC_DATA);
        vm.prank(impostor);
        vm.expectRevert("Identity: sender lacks a MANAGEMENT key");
        issuer.revokeClaimBySignature(sig);
    }

    // --- management key can also sign (management implies CLAIM) ---------

    function test_managementKeyCanSignClaims() public {
        (address adminSigner, uint256 adminPk) = makeAddrAndKey("adminSigner");
        ClaimIssuer issuer2 = new ClaimIssuer(adminSigner); // adminSigner is MANAGEMENT
        bytes memory sig = _sign(adminPk, address(aliceId), Topics.KYC, KYC_DATA);
        assertTrue(issuer2.isClaimValid(address(aliceId), Topics.KYC, sig, KYC_DATA));
    }
}
