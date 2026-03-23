// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {TestSetup} from "../helpers/TestSetup.sol";
import {Types} from "../../libraries/Types.sol";

/// @title AccessControlAttackTest -- Exhaustive unauthorized access tests
/// @notice Every role-restricted function in the system is called from an unauthorized
///         address (stranger). All calls must revert. Also tests role escalation and
///         role revocation scenarios.
contract AccessControlAttackTest is TestSetup {

    bytes32 public templateId;
    bytes32 public instanceId;

    function setUp() public override {
        super.setUp();
        (templateId, instanceId) = _fullSetup();
    }

    // ========================================================================
    // ContractTemplates -- ADMIN_ROLE restricted
    // ========================================================================

    /// @notice Stranger cannot create templates
    function test_unauthorized_createTemplate_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        templates.createTemplate(
            "Evil Template",
            Types.ContractType.RPS,
            _encodeConditions(1e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            300,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
    }

    /// @notice Stranger cannot update templates
    function test_unauthorized_updateTemplate_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        templates.updateTemplate(
            templateId,
            "Evil Update",
            _encodeConditions(1e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            300,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
    }

    /// @notice Stranger cannot activate templates
    function test_unauthorized_activateTemplate_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        templates.activateTemplate(templateId);
    }

    /// @notice Stranger cannot deactivate templates
    function test_unauthorized_deactivateTemplate_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        templates.deactivateTemplate(templateId);
    }

    /// @notice Stranger cannot pause templates
    function test_unauthorized_pauseTemplates_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        templates.pause();
    }

    /// @notice Stranger cannot unpause templates
    function test_unauthorized_unpauseTemplates_reverts() public {
        vm.prank(admin);
        templates.pause();

        vm.prank(stranger);
        vm.expectRevert();
        templates.unpause();
    }

    // ========================================================================
    // ContractInstances -- SYSTEM_ROLE, CONTRACT_ROLE, ADMIN_ROLE restricted
    // ========================================================================

    /// @notice Stranger cannot create instances (requires SYSTEM_ROLE)
    function test_unauthorized_createInstance_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.createInstance(templateId, abi.encode("evil"));
    }

    /// @notice Stranger cannot activate instances (requires SYSTEM_ROLE)
    function test_unauthorized_activateInstance_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.activateInstance(instanceId);
    }

    /// @notice Stranger cannot complete instances (requires CONTRACT_ROLE)
    function test_unauthorized_completeInstance_reverts() public {
        _activate(instanceId);

        vm.prank(stranger);
        vm.expectRevert();
        instances.completeInstance(instanceId);
    }

    /// @notice Stranger cannot dispute instances (requires CONTRACT_ROLE)
    function test_unauthorized_disputeInstance_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        vm.prank(stranger);
        vm.expectRevert();
        instances.disputeInstance(instanceId);
    }

    /// @notice Stranger cannot resolve instances (requires ADMIN_ROLE or OPERATOR_ROLE)
    function test_unauthorized_resolveInstance_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        // Force to Disputed state via consent dispute
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "I dispute this");

        vm.prank(stranger);
        vm.expectRevert(Types.Unauthorized.selector);
        instances.resolveInstance(instanceId);
    }

    /// @notice Stranger cannot settle instances (requires CONTRACT_ROLE)
    function test_unauthorized_settleInstance_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.settleInstance(instanceId);
    }

    /// @notice Stranger cannot setTxHash (requires SYSTEM_ROLE)
    function test_unauthorized_setTxHash_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.setTxHash(instanceId, bytes32(uint256(1)));
    }

    /// @notice Stranger cannot set cross-contract references (requires DEFAULT_ADMIN_ROLE)
    function test_unauthorized_setPartiesContract_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.setPartiesContract(address(1));
    }

    /// @notice Stranger cannot set results contract reference
    function test_unauthorized_setResultsContract_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.setResultsContract(address(1));
    }

    /// @notice Stranger cannot set consents contract reference
    function test_unauthorized_setConsentsContract_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.setConsentsContract(address(1));
    }

    /// @notice Stranger cannot set settlements contract reference
    function test_unauthorized_setSettlementsContract_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.setSettlementsContract(address(1));
    }

    /// @notice Stranger cannot pause instances contract
    function test_unauthorized_pauseInstances_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.pause();
    }

    // ========================================================================
    // ContractParties -- CONTRACT_ROLE restricted for escrow operations
    // ========================================================================

    /// @notice Stranger cannot release escrow (requires CONTRACT_ROLE)
    function test_unauthorized_releaseEscrow_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        parties.releaseEscrow(instanceId, stranger, 50e18);
    }

    /// @notice Stranger cannot refund escrow (requires CONTRACT_ROLE)
    function test_unauthorized_refundEscrow_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        parties.refundEscrow(instanceId);
    }

    /// @notice Stranger cannot set templates contract on parties
    function test_unauthorized_setTemplatesOnParties_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        parties.setTemplatesContract(address(1));
    }

    /// @notice Stranger cannot pause parties contract
    function test_unauthorized_pauseParties_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        parties.pause();
    }

    // ========================================================================
    // ContractResults -- SERVER_ROLE and ADMIN_ROLE restricted
    // ========================================================================

    /// @notice Stranger cannot report results (requires SERVER_ROLE)
    function test_unauthorized_reportResult_reverts() public {
        _activate(instanceId);

        bytes memory resultData = abi.encode(
            bob, "rock", "scissors", uint256(1), "1-0", false
        );

        vm.prank(stranger);
        vm.expectRevert();
        results.reportResult(
            instanceId,
            resultData,
            Types.ResultSource.System,
            true
        );
    }

    /// @notice Stranger cannot override results (requires ADMIN_ROLE)
    function test_unauthorized_overrideResult_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        // Force to Disputed
        vm.prank(admin);
        consents.submitConsent(instanceId, alice, false, "", "dispute");

        vm.prank(stranger);
        vm.expectRevert();
        results.overrideResult(
            instanceId,
            abi.encode(alice, "paper", "rock", uint256(1), "1-0", false)
        );
    }

    /// @notice Stranger cannot set instances contract on results
    function test_unauthorized_setInstancesOnResults_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        results.setInstancesContract(address(1));
    }

    /// @notice Stranger cannot pause results contract
    function test_unauthorized_pauseResults_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        results.pause();
    }

    // ========================================================================
    // ContractConsents -- SERVER_ROLE restricted
    // ========================================================================

    /// @notice Stranger cannot submit consent (requires SERVER_ROLE)
    function test_unauthorized_submitConsent_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        vm.prank(stranger);
        vm.expectRevert();
        consents.submitConsent(instanceId, alice, true, "", "");
    }

    /// @notice Stranger cannot auto-consent (requires SERVER_ROLE)
    function test_unauthorized_autoConsent_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);

        vm.prank(stranger);
        vm.expectRevert();
        consents.autoConsent(instanceId, alice);
    }

    /// @notice Stranger cannot set contract references on consents
    function test_unauthorized_setInstancesOnConsents_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        consents.setInstancesContract(address(1));
    }

    /// @notice Stranger cannot pause consents contract
    function test_unauthorized_pauseConsents_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        consents.pause();
    }

    // ========================================================================
    // ContractSettlements -- SETTLER_ROLE and ADMIN_ROLE restricted
    // ========================================================================

    /// @notice Stranger cannot settle contracts (requires SETTLER_ROLE)
    function test_unauthorized_settleContract_reverts() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        vm.prank(stranger);
        vm.expectRevert();
        settlements.settleContract(instanceId);
    }

    /// @notice Stranger cannot refund contracts (requires SETTLER_ROLE or ADMIN_ROLE)
    function test_unauthorized_refundContract_reverts() public {
        _activate(instanceId);
        _submitResultDraw(instanceId);
        _bothConsent(instanceId);

        vm.prank(stranger);
        vm.expectRevert(Types.Unauthorized.selector);
        settlements.refundContract(instanceId);
    }

    /// @notice Stranger cannot set treasury (requires DEFAULT_ADMIN_ROLE)
    function test_unauthorized_setTreasury_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        settlements.setTreasury(stranger);
    }

    /// @notice Stranger cannot set contract references on settlements
    function test_unauthorized_setInstancesOnSettlements_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        settlements.setInstancesContract(address(1));
    }

    /// @notice Stranger cannot pause settlements contract
    function test_unauthorized_pauseSettlements_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        settlements.pause();
    }

    // ========================================================================
    // ROLE ESCALATION ATTACKS
    // ========================================================================

    /// @notice Stranger cannot grant themselves roles
    function test_roleEscalation_grantRole_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.grantRole(ADMIN_ROLE, stranger);
    }

    /// @notice Stranger cannot grant themselves DEFAULT_ADMIN_ROLE
    function test_roleEscalation_grantDefaultAdmin_reverts() public {
        bytes32 defaultAdminRole = instances.DEFAULT_ADMIN_ROLE();
        vm.prank(stranger);
        vm.expectRevert();
        instances.grantRole(defaultAdminRole, stranger);
    }

    /// @notice Stranger cannot grant themselves SYSTEM_ROLE
    function test_roleEscalation_grantSystemRole_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.grantRole(SYSTEM_ROLE, stranger);
    }

    /// @notice Stranger cannot grant themselves CONTRACT_ROLE
    function test_roleEscalation_grantContractRole_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.grantRole(CONTRACT_ROLE, stranger);
    }

    /// @notice Stranger cannot grant themselves SETTLER_ROLE
    function test_roleEscalation_grantSettlerRole_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        settlements.grantRole(SETTLER_ROLE, stranger);
    }

    /// @notice Stranger cannot grant themselves SERVER_ROLE
    function test_roleEscalation_grantServerRole_reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        results.grantRole(SERVER_ROLE, stranger);
    }

    // ========================================================================
    // ROLE REVOCATION TESTS
    // ========================================================================

    /// @notice Admin can revoke SETTLER_ROLE and settler can no longer settle
    function test_roleRevocation_settler_cannot_settle() public {
        _activate(instanceId);
        _submitResultBobWins(instanceId);
        _bothConsent(instanceId);

        // Admin revokes SETTLER_ROLE from admin (itself)
        address settler = makeAddr("settler");
        vm.startPrank(admin);
        settlements.grantRole(SETTLER_ROLE, settler);
        vm.stopPrank();

        // Settler can settle
        vm.prank(settler);
        settlements.settleContract(instanceId);

        // Create a new instance for the revocation test
        vm.prank(admin);
        bytes32 tplId2 = templates.createTemplate(
            "RPS Revocation Test",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        bytes32 instId2 = _createInstance(tplId2);

        // Mint more tokens for alice and bob
        token.mint(alice, MINT_AMOUNT);
        token.mint(bob, MINT_AMOUNT);

        vm.prank(alice);
        parties.joinContract(instId2, CHALLENGER_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
        vm.prank(bob);
        parties.joinContract(instId2, OPPONENT_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);

        _activate(instId2);
        _submitResultBobWins(instId2);
        _bothConsent(instId2);

        // Revoke SETTLER_ROLE
        vm.prank(admin);
        settlements.revokeRole(SETTLER_ROLE, settler);

        // Settler can no longer settle
        vm.prank(settler);
        vm.expectRevert();
        settlements.settleContract(instId2);
    }

    /// @notice Admin can revoke SERVER_ROLE and server can no longer report results
    function test_roleRevocation_server_cannot_report() public {
        address server = makeAddr("server");
        vm.prank(admin);
        results.grantRole(SERVER_ROLE, server);

        // Create a new instance
        vm.prank(admin);
        bytes32 tplId2 = templates.createTemplate(
            "RPS Server Revoke",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
        bytes32 instId2 = _createInstance(tplId2);
        token.mint(alice, MINT_AMOUNT);
        token.mint(bob, MINT_AMOUNT);
        vm.prank(alice);
        parties.joinContract(instId2, CHALLENGER_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
        vm.prank(bob);
        parties.joinContract(instId2, OPPONENT_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
        _activate(instId2);

        // Revoke SERVER_ROLE
        vm.prank(admin);
        results.revokeRole(SERVER_ROLE, server);

        // Server can no longer report results
        bytes memory resultData = abi.encode(
            bob, "rock", "scissors", uint256(1), "1-0", false
        );
        vm.prank(server);
        vm.expectRevert();
        results.reportResult(instId2, resultData, Types.ResultSource.System, true);
    }

    /// @notice Stranger cannot revoke roles from other addresses
    function test_stranger_cannot_revokeRole() public {
        vm.prank(stranger);
        vm.expectRevert();
        instances.revokeRole(ADMIN_ROLE, admin);
    }
}
