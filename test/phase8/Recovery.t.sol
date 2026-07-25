// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {RecoverableToken} from "../../src/phase8/RecoverableToken.sol";
import {Identity} from "../../src/phase2/Identity.sol";
import {ClaimIssuer} from "../../src/phase3/ClaimIssuer.sol";
import {Topics} from "../../src/phase3/Topics.sol";
import {ClaimTopicsRegistry} from "../../src/phase4/ClaimTopicsRegistry.sol";
import {TrustedIssuersRegistry} from "../../src/phase4/TrustedIssuersRegistry.sol";
import {IdentityRegistry} from "../../src/phase5/IdentityRegistry.sol";
import {IIdentityRegistry} from "../../src/phase5/interfaces/IIdentityRegistry.sol";
import {ModularCompliance} from "../../src/phase6/ModularCompliance.sol";

contract RecoveryTest is Test {
    ClaimTopicsRegistry internal topics;
    TrustedIssuersRegistry internal tir;
    IdentityRegistry internal reg;
    ModularCompliance internal compliance;
    RecoverableToken internal token;
    ClaimIssuer internal kycIssuer;

    address internal agent = makeAddr("agent");
    address internal alice = makeAddr("alice");
    address internal aliceNewWallet = makeAddr("aliceNewWallet");
    address internal bob = makeAddr("bob");
    address internal claimSigner;
    uint256 internal claimSignerPk;
    address internal kycAdmin = makeAddr("kycAdmin");

    Identity internal aliceId;

    uint16 internal constant FRANCE = 250;
    bytes internal constant KYC_DATA = abi.encode("KYC:PASS");

    function setUp() public {
        (claimSigner, claimSignerPk) = makeAddrAndKey("claimSigner");

        topics = new ClaimTopicsRegistry();
        tir = new TrustedIssuersRegistry();
        topics.addClaimTopic(Topics.KYC);

        kycIssuer = new ClaimIssuer(kycAdmin);
        uint256 claimPurpose = kycIssuer.CLAIM_SIGNER_KEY();
        uint256 ecdsaType = kycIssuer.KEY_TYPE_ECDSA();
        vm.prank(kycAdmin);
        kycIssuer.addKey(keccak256(abi.encode(claimSigner)), claimPurpose, ecdsaType);
        tir.addTrustedIssuer(kycIssuer, _arr1(Topics.KYC));

        reg = new IdentityRegistry(topics, tir);
        reg.addAgent(address(this)); // for onboarding in the test
        compliance = new ModularCompliance();

        token = new RecoverableToken("Acme Share", "ACME", 0, IIdentityRegistry(address(reg)), compliance);
        compliance.bindToken(address(token));
        token.addAgent(agent);
        reg.addAgent(address(token)); // token must be a registry agent to re-register

        aliceId = _onboard(alice);
        _onboard(bob); // bob just needs to be verified to receive
    }

    // ===================================================================
    // Core recovery
    // ===================================================================

    function test_recover_movesPositionToNewWallet() public {
        _mint(alice, 100);
        _linkNewWalletToIdentity(aliceNewWallet);

        vm.prank(agent);
        token.recoverWallet(alice, aliceNewWallet);

        // tokens followed the identity to the new wallet
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(aliceNewWallet), 100);

        // registry now points the NEW wallet at the SAME identity
        assertFalse(reg.contains(alice));
        assertTrue(reg.contains(aliceNewWallet));
        assertEq(address(reg.identity(aliceNewWallet)), address(aliceId));

        // and the new wallet is verified (same claims, same identity)
        assertTrue(reg.isVerified(aliceNewWallet));
    }

    function test_recover_requiresNewWalletIsManagementKey() public {
        _mint(alice, 100);
        // NOTE: aliceNewWallet is NOT added as a key on the identity.
        vm.prank(agent);
        vm.expectRevert("Recovery: new wallet is not a management key on the identity");
        token.recoverWallet(alice, aliceNewWallet);
    }

    function test_recover_onlyAgent() public {
        _mint(alice, 100);
        _linkNewWalletToIdentity(aliceNewWallet);
        vm.prank(bob); // not a token agent
        vm.expectRevert("AgentRole: caller is not an agent");
        token.recoverWallet(alice, aliceNewWallet);
    }

    function test_recover_revertsWhenNothingToRecover() public {
        _linkNewWalletToIdentity(aliceNewWallet);
        vm.prank(agent);
        vm.expectRevert("Recovery: nothing to recover");
        token.recoverWallet(alice, aliceNewWallet);
    }

    // ===================================================================
    // Freeze state is preserved through recovery
    // ===================================================================

    function test_recover_preservesPartialFreeze() public {
        _mint(alice, 100);
        vm.prank(agent);
        token.freezePartialTokens(alice, 40);
        _linkNewWalletToIdentity(aliceNewWallet);

        vm.prank(agent);
        token.recoverWallet(alice, aliceNewWallet);

        assertEq(token.balanceOf(aliceNewWallet), 100);
        assertEq(token.getFrozenTokens(aliceNewWallet), 40); // freeze carried over
    }

    function test_recover_preservesWalletFreeze() public {
        _mint(alice, 100);
        vm.prank(agent);
        token.setAddressFrozen(alice, true);
        _linkNewWalletToIdentity(aliceNewWallet);

        vm.prank(agent);
        token.recoverWallet(alice, aliceNewWallet);

        assertTrue(token.isFrozen(aliceNewWallet)); // e.g. sanctioned holder stays frozen
    }

    // ===================================================================
    // Continuity: the recovered wallet behaves like the old one
    // ===================================================================

    function test_recoveredWallet_canTransfer_oldWalletCannotReceive() public {
        _mint(alice, 100);
        _linkNewWalletToIdentity(aliceNewWallet);
        vm.prank(agent);
        token.recoverWallet(alice, aliceNewWallet);

        // new wallet trades normally
        vm.prank(aliceNewWallet);
        token.transfer(bob, 30);
        assertEq(token.balanceOf(bob), 30);

        // old wallet was removed from the registry -> can no longer receive
        vm.prank(aliceNewWallet);
        vm.expectRevert("Token: recipient identity not verified");
        token.transfer(alice, 10);
    }

    // ===================================================================
    // helpers
    // ===================================================================

    function _onboard(address wallet) private returns (Identity id) {
        id = new Identity(wallet);
        bytes memory sig = _claimSigForIdentity(address(id));
        vm.prank(wallet);
        id.addClaim(Topics.KYC, 1, address(kycIssuer), sig, KYC_DATA, "");
        reg.registerIdentity(wallet, id, FRANCE);
    }

    /// @dev The person proves the new wallet is theirs by adding it as a
    ///      MANAGEMENT key on their identity (done by an existing manager).
    function _linkNewWalletToIdentity(address newWallet) private {
        vm.prank(alice); // alice is a management key on aliceId
        aliceId.addKey(keccak256(abi.encode(newWallet)), 1, 1); // purpose MANAGEMENT, type ECDSA
    }

    function _claimSigForIdentity(address identityAddr) private view returns (bytes memory) {
        bytes32 dataHash = keccak256(abi.encode(identityAddr, Topics.KYC, KYC_DATA));
        bytes32 prefixed = MessageHashUtils.toEthSignedMessageHash(dataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimSignerPk, prefixed);
        return abi.encodePacked(r, s, v);
    }

    function _mint(address to, uint256 amount) private {
        vm.prank(agent);
        token.mint(to, amount);
    }

    function _arr1(uint256 a) private pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = a;
    }
}
