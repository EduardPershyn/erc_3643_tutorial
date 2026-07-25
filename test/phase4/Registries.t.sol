// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ClaimTopicsRegistry} from "../../src/phase4/ClaimTopicsRegistry.sol";
import {TrustedIssuersRegistry} from "../../src/phase4/TrustedIssuersRegistry.sol";
import {ITrustedIssuersRegistry} from "../../src/phase4/interfaces/ITrustedIssuersRegistry.sol";
import {IClaimIssuer} from "../../src/phase3/interfaces/IClaimIssuer.sol";
import {ClaimIssuer} from "../../src/phase3/ClaimIssuer.sol";
import {Topics} from "../../src/phase3/Topics.sol";

contract RegistriesTest is Test {
    ClaimTopicsRegistry internal topics;
    TrustedIssuersRegistry internal tir;

    // Trusted issuers (real-world: Deloitte for KYC/Country, Chainalysis for AML)
    ClaimIssuer internal deloitte;
    ClaimIssuer internal chainalysis;
    address internal notOwner = makeAddr("notOwner");
    address internal randomWallet = makeAddr("randomMetaMaskWallet");

    function setUp() public {
        topics = new ClaimTopicsRegistry();
        tir = new TrustedIssuersRegistry();
        // owner of both registries is address(this) (the test contract)

        deloitte = new ClaimIssuer(makeAddr("deloitteAdmin"));
        chainalysis = new ClaimIssuer(makeAddr("chainalysisAdmin"));
    }

    // ===================================================================
    // ClaimTopicsRegistry
    // ===================================================================

    function test_claimTopics_addAndGet() public {
        topics.addClaimTopic(Topics.KYC);
        topics.addClaimTopic(Topics.COUNTRY);

        uint256[] memory t = topics.getClaimTopics();
        assertEq(t.length, 2);
        assertEq(t[0], Topics.KYC);
        assertEq(t[1], Topics.COUNTRY);
    }

    function test_claimTopics_noDuplicates() public {
        topics.addClaimTopic(Topics.KYC);
        vm.expectRevert("CTR: topic already exists");
        topics.addClaimTopic(Topics.KYC);
    }

    function test_claimTopics_remove() public {
        topics.addClaimTopic(Topics.KYC);
        topics.addClaimTopic(Topics.COUNTRY);
        topics.removeClaimTopic(Topics.KYC);

        uint256[] memory t = topics.getClaimTopics();
        assertEq(t.length, 1);
        assertEq(t[0], Topics.COUNTRY); // swap-pop moved COUNTRY into slot 0
    }

    function test_claimTopics_removeMissingReverts() public {
        vm.expectRevert("CTR: topic does not exist");
        topics.removeClaimTopic(Topics.AML);
    }

    function test_claimTopics_onlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        topics.addClaimTopic(Topics.KYC);
    }

    // ===================================================================
    // TrustedIssuersRegistry — the deliverable
    // ===================================================================

    function test_isTrustedIssuer_trueForRegistered_falseForRandomWallet() public {
        uint256[] memory kycCountry = _arr2(Topics.KYC, Topics.COUNTRY);
        tir.addTrustedIssuer(deloitte, kycCountry);

        // Trusted: Deloitte. Not trusted: a random MetaMask wallet.
        assertTrue(tir.isTrustedIssuer(address(deloitte)));
        assertFalse(tir.isTrustedIssuer(randomWallet));
    }

    function test_addTrustedIssuer_emitsAndStoresTopics() public {
        uint256[] memory kycCountry = _arr2(Topics.KYC, Topics.COUNTRY);

        vm.expectEmit(true, false, false, true);
        emit ITrustedIssuersRegistry.TrustedIssuerAdded(deloitte, kycCountry);
        tir.addTrustedIssuer(deloitte, kycCountry);

        assertTrue(tir.hasClaimTopic(address(deloitte), Topics.KYC));
        assertTrue(tir.hasClaimTopic(address(deloitte), Topics.COUNTRY));
        // trust is per-topic: Deloitte is NOT trusted for AML here
        assertFalse(tir.hasClaimTopic(address(deloitte), Topics.AML));

        uint256[] memory got = tir.getTrustedIssuerClaimTopics(deloitte);
        assertEq(got.length, 2);
    }

    function test_getTrustedIssuersForClaimTopic() public {
        tir.addTrustedIssuer(deloitte, _arr2(Topics.KYC, Topics.COUNTRY));
        tir.addTrustedIssuer(chainalysis, _arr1(Topics.AML));

        IClaimIssuer[] memory kycIssuers = tir.getTrustedIssuersForClaimTopic(Topics.KYC);
        assertEq(kycIssuers.length, 1);
        assertEq(address(kycIssuers[0]), address(deloitte));

        IClaimIssuer[] memory amlIssuers = tir.getTrustedIssuersForClaimTopic(Topics.AML);
        assertEq(amlIssuers.length, 1);
        assertEq(address(amlIssuers[0]), address(chainalysis));

        assertEq(tir.getTrustedIssuers().length, 2);
    }

    function test_addTrustedIssuer_revertsOnDuplicateIssuer() public {
        tir.addTrustedIssuer(deloitte, _arr1(Topics.KYC));
        vm.expectRevert("TIR: issuer already exists");
        tir.addTrustedIssuer(deloitte, _arr1(Topics.COUNTRY));
    }

    function test_addTrustedIssuer_revertsOnEmptyTopics() public {
        uint256[] memory empty = new uint256[](0);
        vm.expectRevert("TIR: no topics");
        tir.addTrustedIssuer(deloitte, empty);
    }

    function test_addTrustedIssuer_revertsOnZeroIssuer() public {
        vm.expectRevert("TIR: zero issuer");
        tir.addTrustedIssuer(IClaimIssuer(address(0)), _arr1(Topics.KYC));
    }

    function test_addTrustedIssuer_revertsOnDuplicateTopic() public {
        vm.expectRevert("TIR: duplicate topic");
        tir.addTrustedIssuer(deloitte, _arr2(Topics.KYC, Topics.KYC));
    }

    function test_updateIssuerClaimTopics_rewiresPerTopicLookup() public {
        tir.addTrustedIssuer(deloitte, _arr1(Topics.KYC));
        assertEq(tir.getTrustedIssuersForClaimTopic(Topics.KYC).length, 1);

        // Re-scope Deloitte from KYC to COUNTRY.
        tir.updateIssuerClaimTopics(deloitte, _arr1(Topics.COUNTRY));

        assertEq(tir.getTrustedIssuersForClaimTopic(Topics.KYC).length, 0);
        assertEq(tir.getTrustedIssuersForClaimTopic(Topics.COUNTRY).length, 1);
        assertFalse(tir.hasClaimTopic(address(deloitte), Topics.KYC));
        assertTrue(tir.hasClaimTopic(address(deloitte), Topics.COUNTRY));
    }

    function test_removeTrustedIssuer_clearsEverything() public {
        tir.addTrustedIssuer(deloitte, _arr2(Topics.KYC, Topics.COUNTRY));
        tir.removeTrustedIssuer(deloitte);

        assertFalse(tir.isTrustedIssuer(address(deloitte)));
        assertEq(tir.getTrustedIssuers().length, 0);
        assertEq(tir.getTrustedIssuersForClaimTopic(Topics.KYC).length, 0);
        assertEq(tir.getTrustedIssuersForClaimTopic(Topics.COUNTRY).length, 0);
    }

    function test_removeTrustedIssuer_revertsWhenMissing() public {
        vm.expectRevert("TIR: issuer does not exist");
        tir.removeTrustedIssuer(deloitte);
    }

    function test_mutations_onlyOwner() public {
        vm.startPrank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        tir.addTrustedIssuer(deloitte, _arr1(Topics.KYC));
        vm.stopPrank();
    }

    // --- helpers --------------------------------------------------------

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
