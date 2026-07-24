// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {OpenToken} from "../../src/phase1/OpenToken.sol";
import {RestrictedToken} from "../../src/phase1/RestrictedToken.sol";

/// @notice Phase 1 is conceptual; these tests turn its three questions into
///         executable proofs. Each test name is one Phase 1 question.
contract Phase1Test is Test {
    address internal agent = makeAddr("agent");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    // ==================================================================
    // Q1: Why can't institutions simply use ERC-20?
    //     Because a plain ERC-20 lets value flow to ANY address, with no
    //     way for the issuer to say no.
    // ==================================================================
    function test_Q1_openToken_sendsToAnyoneUnconditionally() public {
        OpenToken token = new OpenToken();
        token.mint(alice, 100e18);

        // Alice can send to a completely unknown wallet. No check, no revert.
        vm.prank(alice);
        token.transfer(stranger, 100e18);

        assertEq(token.balanceOf(stranger), 100e18);
    }

    // ==================================================================
    // Q3: Why must transfers be restricted?
    //     A security token gates every holder-to-holder transfer. Sending
    //     to an unverified wallet must fail; it must succeed only once both
    //     sides are verified.
    // ==================================================================
    function test_Q3_restrictedToken_blocksUnverifiedRecipient() public {
        RestrictedToken token = _deployRestrictedWithVerifiedAlice(100e18);

        // Bob is NOT verified yet -> transfer reverts.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RestrictedToken.NotVerified.selector, bob));
        token.transfer(bob, 40e18);

        // Agent verifies Bob -> same transfer now succeeds.
        vm.prank(agent);
        token.setVerified(bob, true);

        vm.prank(alice);
        token.transfer(bob, 40e18);

        assertEq(token.balanceOf(alice), 60e18);
        assertEq(token.balanceOf(bob), 40e18);
    }

    /// @notice A frozen (e.g. sanctioned) holder cannot move tokens — the
    ///         issuer retains control after issuance, unlike plain ERC-20.
    function test_Q3_restrictedToken_frozenHolderCannotTransfer() public {
        RestrictedToken token = _deployRestrictedWithVerifiedAlice(100e18);
        vm.prank(agent);
        token.setVerified(bob, true);

        vm.prank(agent);
        token.setFrozen(alice, true);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RestrictedToken.AccountFrozen.selector, alice));
        token.transfer(bob, 10e18);
    }

    // ==================================================================
    // Q2: Why is `wallet = identity` a problem?
    //     Because tokens are bound to the identity, not the key. If a holder
    //     loses their wallet, the agent/identity can rotate to a new wallet
    //     and the balance follows — impossible with a plain ERC-20.
    // ==================================================================
    function test_Q2_restrictedToken_recoveryMovesBalanceToNewWallet() public {
        RestrictedToken token = _deployRestrictedWithVerifiedAlice(100e18);
        address aliceNewWallet = makeAddr("aliceNewWallet");

        vm.prank(agent);
        token.recover(alice, aliceNewWallet);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(aliceNewWallet), 100e18);
        assertTrue(token.isVerified(aliceNewWallet));
    }

    /// @notice The contrast: a plain ERC-20 has NO recovery. A lost key means
    ///         lost value, full stop. We prove the mechanism simply isn't there.
    function test_Q2_openToken_hasNoRecoveryMechanism() public {
        OpenToken token = new OpenToken();
        token.mint(alice, 100e18);
        // Nothing on OpenToken can move Alice's balance without Alice's key.
        // The absence is the lesson; there is no function to call.
        assertEq(token.balanceOf(alice), 100e18);
    }

    // --- helpers --------------------------------------------------------

    function _deployRestrictedWithVerifiedAlice(uint256 amount)
        internal
        returns (RestrictedToken token)
    {
        vm.prank(agent);
        token = new RestrictedToken();

        vm.startPrank(agent);
        token.setVerified(alice, true);
        token.mint(alice, amount);
        vm.stopPrank();
    }
}
