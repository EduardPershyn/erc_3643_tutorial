// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ModularCompliance} from "../../src/phase6/ModularCompliance.sol";
import {IModule} from "../../src/phase6/interfaces/IModule.sol";
import {TransferLockModule} from "../../src/phase6/modules/TransferLockModule.sol";
import {CountryAllowModule} from "../../src/phase6/modules/CountryAllowModule.sol";
import {MaxHolderModule} from "../../src/phase6/modules/MaxHolderModule.sol";
import {IdentityRegistry} from "../../src/phase5/IdentityRegistry.sol";
import {Identity} from "../../src/phase2/Identity.sol";
import {ClaimTopicsRegistry} from "../../src/phase4/ClaimTopicsRegistry.sol";
import {TrustedIssuersRegistry} from "../../src/phase4/TrustedIssuersRegistry.sol";

/// @notice The test contract plays the role of the bound TOKEN: it calls the
///         hooks (transferred/created/destroyed) directly, as the token would.
contract ComplianceTest is Test {
    ModularCompliance internal compliance;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal notToken = makeAddr("notToken");

    uint16 internal constant FRANCE = 250;
    uint16 internal constant US = 840;

    function setUp() public {
        compliance = new ModularCompliance();
        compliance.bindToken(address(this)); // this test == the token
    }

    // ===================================================================
    // Engine basics
    // ===================================================================

    function test_canTransfer_trueWithNoModules() public view {
        assertTrue(compliance.canTransfer(alice, bob, 100));
    }

    function test_addRemoveModule() public {
        TransferLockModule m = new TransferLockModule(0);
        m.bindCompliance(address(compliance));

        compliance.addModule(m);
        assertEq(compliance.getModules().length, 1);

        compliance.removeModule(m);
        assertEq(compliance.getModules().length, 0);
    }

    function test_addModule_onlyOwner() public {
        TransferLockModule m = new TransferLockModule(0);
        vm.prank(notToken);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notToken));
        compliance.addModule(m);
    }

    function test_hooks_onlyBoundToken() public {
        vm.prank(notToken);
        vm.expectRevert("Compliance: caller is not the bound token");
        compliance.transferred(alice, bob, 1);
    }

    function test_moduleAction_onlyBoundCompliance() public {
        MaxHolderModule m = new MaxHolderModule(10);
        m.bindCompliance(address(compliance));
        // Calling the module directly (not via compliance) must fail.
        vm.expectRevert("Module: caller is not the bound compliance");
        m.moduleMintAction(alice, 1);
    }

    // ===================================================================
    // Rule #1 — TransferLockModule ("no transfers before <time>")
    // ===================================================================

    function test_transferLock_blocksThenAllows() public {
        uint256 release = block.timestamp + 365 days;
        TransferLockModule m = new TransferLockModule(release);
        m.bindCompliance(address(compliance));
        compliance.addModule(m);

        assertFalse(compliance.canTransfer(alice, bob, 100)); // locked

        vm.warp(release);
        assertTrue(compliance.canTransfer(alice, bob, 100)); // unlocked
    }

    // ===================================================================
    // Rule #2 — CountryAllowModule ("must be an EU resident")
    // ===================================================================

    function test_countryAllow_gatesByReceiverCountry() public {
        IdentityRegistry reg = _freshRegistry();
        reg.addAgent(address(this));
        // register alice as FRANCE, bob as US, each with a throwaway identity
        reg.registerIdentity(alice, new Identity(alice), FRANCE);
        reg.registerIdentity(bob, new Identity(bob), US);

        CountryAllowModule m = new CountryAllowModule(reg);
        m.bindCompliance(address(compliance));
        m.allowCountry(FRANCE);
        compliance.addModule(m);

        assertTrue(compliance.canTransfer(bob, alice, 100)); // to FRANCE -> ok
        assertFalse(compliance.canTransfer(alice, bob, 100)); // to US -> blocked
    }

    // ===================================================================
    // Rule #3 — MaxHolderModule ("max N holders"), stateful
    // ===================================================================

    function test_maxHolders_blocksNewHolderAtCap_freesSlotOnExit() public {
        MaxHolderModule m = new MaxHolderModule(2);
        m.bindCompliance(address(compliance));
        compliance.addModule(m);

        // Mint to alice and bob -> 2 holders (at cap).
        compliance.created(alice, 100);
        compliance.created(bob, 100);
        assertEq(m.holderCount(), 2);

        // A brand-new holder (carol) is blocked at the cap...
        assertFalse(compliance.canTransfer(bob, carol, 10));
        // ...but an existing holder can still receive.
        assertTrue(compliance.canTransfer(bob, alice, 10));

        // alice sends her whole balance to bob -> alice drops to 0 holders.
        compliance.transferred(alice, bob, 100);
        assertEq(m.holderCount(), 1);
        assertEq(m.balanceOfMirror(alice), 0);
        assertEq(m.balanceOfMirror(bob), 200);

        // Slot freed -> carol can now become a holder.
        assertTrue(compliance.canTransfer(bob, carol, 10));
    }

    function test_maxHolders_burnDecrementsHolderCount() public {
        MaxHolderModule m = new MaxHolderModule(5);
        m.bindCompliance(address(compliance));
        compliance.addModule(m);

        compliance.created(alice, 100);
        assertEq(m.holderCount(), 1);
        compliance.destroyed(alice, 100);
        assertEq(m.holderCount(), 0);
    }

    // ===================================================================
    // Aggregation — a transfer must satisfy ALL modules (the plan's combo)
    // ===================================================================

    function test_aggregate_allThreeRulesMustPass() public {
        IdentityRegistry reg = _freshRegistry();
        reg.addAgent(address(this));
        reg.registerIdentity(alice, new Identity(alice), FRANCE);
        reg.registerIdentity(bob, new Identity(bob), FRANCE);

        uint256 release = block.timestamp + 10 days;

        TransferLockModule lock = new TransferLockModule(release);
        CountryAllowModule country = new CountryAllowModule(reg);
        MaxHolderModule cap = new MaxHolderModule(2);
        lock.bindCompliance(address(compliance));
        country.bindCompliance(address(compliance));
        cap.bindCompliance(address(compliance));
        country.allowCountry(FRANCE);
        compliance.addModule(lock);
        compliance.addModule(country);
        compliance.addModule(cap);

        // seed alice & bob as holders (2, at cap)
        compliance.created(alice, 100);
        compliance.created(bob, 100);

        // Still locked -> blocked even though country & cap are fine.
        assertFalse(compliance.canTransfer(alice, bob, 10));

        vm.warp(release); // unlock

        // Now alice -> bob passes all three (FRANCE ok, bob existing holder).
        assertTrue(compliance.canTransfer(alice, bob, 10));

        // alice -> carol fails: carol has no allowed country AND is a new holder at cap.
        assertFalse(compliance.canTransfer(alice, carol, 10));
    }

    // --- helpers --------------------------------------------------------

    function _freshRegistry() private returns (IdentityRegistry) {
        return new IdentityRegistry(new ClaimTopicsRegistry(), new TrustedIssuersRegistry());
    }
}
