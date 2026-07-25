// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {Token} from "../../src/phase7/Token.sol";
import {Identity} from "../../src/phase2/Identity.sol";
import {ClaimIssuer} from "../../src/phase3/ClaimIssuer.sol";
import {Topics} from "../../src/phase3/Topics.sol";
import {ClaimTopicsRegistry} from "../../src/phase4/ClaimTopicsRegistry.sol";
import {TrustedIssuersRegistry} from "../../src/phase4/TrustedIssuersRegistry.sol";
import {IdentityRegistry} from "../../src/phase5/IdentityRegistry.sol";
import {IIdentityRegistry} from "../../src/phase5/interfaces/IIdentityRegistry.sol";
import {ModularCompliance} from "../../src/phase6/ModularCompliance.sol";
import {MaxHolderModule} from "../../src/phase6/modules/MaxHolderModule.sol";

/// @notice Full-stack integration: identity + claims + registries + compliance
///         + token. This is the assembled ERC-3643 system.
contract TokenTest is Test {
    // stack
    ClaimTopicsRegistry internal topics;
    TrustedIssuersRegistry internal tir;
    IdentityRegistry internal reg;
    ModularCompliance internal compliance;
    Token internal token;
    ClaimIssuer internal kycIssuer;

    // actors
    address internal agent = makeAddr("agent");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol"); // never verified
    address internal claimSigner;
    uint256 internal claimSignerPk;
    address internal kycAdmin = makeAddr("kycAdmin");

    uint16 internal constant FRANCE = 250;
    bytes internal constant KYC_DATA = abi.encode("KYC:PASS");

    function setUp() public {
        (claimSigner, claimSignerPk) = makeAddrAndKey("claimSigner");

        // Phase 4 registries: require KYC, trust our issuer for it.
        topics = new ClaimTopicsRegistry();
        tir = new TrustedIssuersRegistry();
        topics.addClaimTopic(Topics.KYC);

        kycIssuer = new ClaimIssuer(kycAdmin);
        uint256 claimPurpose = kycIssuer.CLAIM_SIGNER_KEY();
        uint256 ecdsaType = kycIssuer.KEY_TYPE_ECDSA();
        vm.prank(kycAdmin);
        kycIssuer.addKey(keccak256(abi.encode(claimSigner)), claimPurpose, ecdsaType);
        tir.addTrustedIssuer(kycIssuer, _arr1(Topics.KYC));

        // Phase 5 registry + Phase 6 compliance
        reg = new IdentityRegistry(topics, tir);
        reg.addAgent(address(this));
        compliance = new ModularCompliance();

        // Phase 7 token, wired together
        token = new Token("Acme Share", "ACME", 0, IIdentityRegistry(address(reg)), compliance);
        compliance.bindToken(address(token));
        token.addAgent(agent);

        // onboard alice & bob as verified holders
        _onboard(alice);
        _onboard(bob);
    }

    // ===================================================================
    // Mint — identity-gated issuance
    // ===================================================================

    function test_mint_toVerified_succeeds() public {
        vm.prank(agent);
        token.mint(alice, 100);
        assertEq(token.balanceOf(alice), 100);
    }

    function test_mint_toUnverified_reverts() public {
        vm.prank(agent);
        vm.expectRevert("Token: recipient identity not verified");
        token.mint(carol, 100);
    }

    function test_mint_onlyAgent() public {
        vm.prank(alice);
        vm.expectRevert("AgentRole: caller is not an agent");
        token.mint(alice, 100);
    }

    // ===================================================================
    // Transfer — the full flow
    // ===================================================================

    function test_transfer_betweenVerified_succeeds() public {
        _mint(alice, 100);

        vm.prank(alice);
        token.transfer(bob, 40);

        assertEq(token.balanceOf(alice), 60);
        assertEq(token.balanceOf(bob), 40);
    }

    function test_transfer_toUnverified_reverts() public {
        _mint(alice, 100);
        vm.prank(alice);
        vm.expectRevert("Token: recipient identity not verified");
        token.transfer(carol, 10);
    }

    function test_transfer_revertsWhenPaused() public {
        _mint(alice, 100);
        vm.prank(agent);
        token.pause();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(bob, 10);

        vm.prank(agent);
        token.unpause();
        vm.prank(alice);
        token.transfer(bob, 10);
        assertEq(token.balanceOf(bob), 10);
    }

    function test_transfer_blockedByCompliance() public {
        // Add a MaxHolder cap of 1: alice already holds, bob would be #2.
        MaxHolderModule cap = new MaxHolderModule(1);
        cap.bindCompliance(address(compliance));
        compliance.addModule(cap);

        _mint(alice, 100); // holder #1

        vm.prank(alice);
        vm.expectRevert("Token: transfer breaks compliance");
        token.transfer(bob, 10); // bob would be a 2nd holder -> blocked
    }

    function test_transferFrom_withApproval() public {
        _mint(alice, 100);
        vm.prank(alice);
        token.approve(address(this), 30);

        token.transferFrom(alice, bob, 30);
        assertEq(token.balanceOf(bob), 30);
        assertEq(token.allowance(alice, address(this)), 0);
    }

    // ===================================================================
    // Freezing
    // ===================================================================

    function test_frozenWallet_cannotSendOrReceive() public {
        _mint(alice, 100);

        vm.prank(agent);
        token.setAddressFrozen(alice, true);
        vm.prank(alice);
        vm.expectRevert("Token: sender wallet frozen");
        token.transfer(bob, 10);

        vm.prank(agent);
        token.setAddressFrozen(alice, false);
        vm.prank(agent);
        token.setAddressFrozen(bob, true);
        vm.prank(alice);
        vm.expectRevert("Token: recipient wallet frozen");
        token.transfer(bob, 10);
    }

    function test_partialFreeze_limitsTransferableBalance() public {
        _mint(alice, 100);
        vm.prank(agent);
        token.freezePartialTokens(alice, 70); // only 30 free

        vm.prank(alice);
        vm.expectRevert("Token: insufficient unfrozen balance");
        token.transfer(bob, 40);

        vm.prank(alice);
        token.transfer(bob, 30); // within free balance
        assertEq(token.balanceOf(bob), 30);
        assertEq(token.getFrozenTokens(alice), 70);
    }

    // ===================================================================
    // Agent enforcement: forcedTransfer & burn
    // ===================================================================

    function test_forcedTransfer_movesEvenFrozenTokens() public {
        _mint(alice, 100);
        vm.prank(agent);
        token.freezePartialTokens(alice, 100); // everything frozen

        // A normal transfer is impossible, but the agent can force it.
        vm.prank(agent);
        token.forcedTransfer(alice, bob, 60);

        assertEq(token.balanceOf(alice), 40);
        assertEq(token.balanceOf(bob), 60);
        assertEq(token.getFrozenTokens(alice), 40); // 100 - 60 unfrozen to move
    }

    function test_forcedTransfer_stillRequiresVerifiedRecipient() public {
        _mint(alice, 100);
        vm.prank(agent);
        vm.expectRevert("Token: recipient identity not verified");
        token.forcedTransfer(alice, carol, 10);
    }

    function test_burn_eatsIntoFrozen() public {
        _mint(alice, 100);
        vm.prank(agent);
        token.freezePartialTokens(alice, 90);

        vm.prank(agent);
        token.burn(alice, 95); // 10 free + 85 from frozen

        assertEq(token.balanceOf(alice), 5);
        assertEq(token.getFrozenTokens(alice), 5); // 90 - 85
    }

    // ===================================================================
    // The Phase 10 headline: revoke KYC -> transfer fails
    // ===================================================================

    function test_revokingKyc_blocksFurtherTransfersToHolder() public {
        _mint(alice, 100);
        // works while bob is verified
        vm.prank(alice);
        token.transfer(bob, 10);
        assertEq(token.balanceOf(bob), 10);

        // KYC provider revokes bob's claim -> he is no longer verified
        bytes memory bobSig = _claimSigOf(bob);
        vm.prank(kycAdmin);
        kycIssuer.revokeClaimBySignature(bobSig);
        assertFalse(reg.isVerified(bob));

        vm.prank(alice);
        vm.expectRevert("Token: recipient identity not verified");
        token.transfer(bob, 10);
    }

    // ===================================================================
    // Access control on wiring
    // ===================================================================

    function test_setCompliance_onlyOwner() public {
        ModularCompliance c2 = new ModularCompliance();
        vm.prank(agent); // agent is not owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, agent));
        token.setCompliance(c2);
    }

    // ===================================================================
    // helpers
    // ===================================================================

    /// @dev Deploy an identity for `wallet`, give it a valid KYC claim, register it.
    function _onboard(address wallet) private {
        Identity id = new Identity(wallet);
        bytes memory sig = _claimSigForIdentity(address(id));
        vm.prank(wallet);
        id.addClaim(Topics.KYC, 1, address(kycIssuer), sig, KYC_DATA, "");
        reg.registerIdentity(wallet, id, FRANCE);
    }

    /// @dev The claim binds to the identity contract's address.
    function _claimSigForIdentity(address identityAddr) private view returns (bytes memory) {
        bytes32 dataHash = keccak256(abi.encode(identityAddr, Topics.KYC, KYC_DATA));
        bytes32 prefixed = MessageHashUtils.toEthSignedMessageHash(dataHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimSignerPk, prefixed);
        return abi.encodePacked(r, s, v);
    }

    function _claimSigOf(address wallet) private view returns (bytes memory) {
        return _claimSigForIdentity(address(reg.identity(wallet)));
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
