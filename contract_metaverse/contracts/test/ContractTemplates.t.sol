// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TestSetup} from "./helpers/TestSetup.sol";
import {Types} from "../libraries/Types.sol";
import {IContractTemplates} from "../interfaces/IContractTemplates.sol";

/// @title ContractTemplatesTest -- Tests for template CRUD operations and access control
contract ContractTemplatesTest is TestSetup {
    // ========================================================================
    // createTemplate — Happy path
    // ========================================================================

    /// @notice Creating a template returns a non-zero ID and increments count
    function test_createTemplate_Success() public {
        bytes32 templateId = _createRPSTemplate();
        assertTrue(templateId != bytes32(0), "Template ID should be non-zero");
        assertEq(templates.getTemplateCount(), 1, "Template count should be 1");
    }

    /// @notice Creating a template emits TemplateCreated event
    function test_createTemplate_EmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(false, true, true, false);
        emit IContractTemplates.TemplateCreated(
            bytes32(0), // templateId not known ahead of time
            Types.ContractType.RPS,
            admin,
            "RPS Event Template",
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional
        );
        templates.createTemplate(
            "RPS Event Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
    }

    /// @notice Template data is stored correctly and retrievable
    function test_createTemplate_DataStoredCorrectly() public {
        bytes32 templateId = _createRPSTemplate();
        Types.Template memory t = templates.getTemplate(templateId);

        assertEq(uint8(t.contractType), uint8(Types.ContractType.RPS));
        assertEq(uint8(t.paymentType), uint8(Types.PaymentType.IXFreePoint));
        assertTrue(t.isActive, "Template should be active on creation");
        assertEq(t.feeRateBps, FEE_RATE_BPS);
        assertEq(t.createdBy, admin);
    }

    // ========================================================================
    // createTemplate — Revert cases
    // ========================================================================

    /// @notice Unauthorized caller cannot create a template
    function testRevert_createTemplate_Unauthorized() public {
        vm.prank(stranger);
        vm.expectRevert();
        templates.createTemplate(
            "Unauthorized Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
    }

    /// @notice Cannot create template when contract is paused
    function testRevert_createTemplate_WhenPaused() public {
        vm.prank(admin);
        templates.pause();

        vm.prank(admin);
        vm.expectRevert();
        templates.createTemplate(
            "Paused Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
    }

    /// @notice Cannot create template with fee rate above 50% (5000 bps)
    function testRevert_createTemplate_InvalidFeeRate() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.InvalidFeeRate.selector, uint16(5001)));
        templates.createTemplate(
            "High Fee Template",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            5001,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
    }

    /// @notice Cannot create template with duplicate name
    function testRevert_createTemplate_DuplicateName() public {
        _createRPSTemplate();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.TemplateNameExists.selector, "RPS Casual Lobby 1"));
        templates.createTemplate(
            "RPS Casual Lobby 1",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
    }

    /// @notice Cannot create template with empty name
    function testRevert_createTemplate_EmptyName() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.InvalidAmount.selector));
        templates.createTemplate(
            "",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );
    }

    // ========================================================================
    // activateTemplate / deactivateTemplate
    // ========================================================================

    /// @notice Activate and deactivate a template toggles isActive
    function test_activateDeactivateTemplate_Success() public {
        bytes32 templateId = _createRPSTemplate();
        assertTrue(templates.isTemplateActive(templateId), "Should be active after creation");

        vm.prank(admin);
        templates.deactivateTemplate(templateId);
        assertFalse(templates.isTemplateActive(templateId), "Should be inactive after deactivation");

        vm.prank(admin);
        templates.activateTemplate(templateId);
        assertTrue(templates.isTemplateActive(templateId), "Should be active after reactivation");
    }

    /// @notice Deactivate emits TemplateDeactivated event
    function test_deactivateTemplate_EmitsEvent() public {
        bytes32 templateId = _createRPSTemplate();

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit IContractTemplates.TemplateDeactivated(templateId);
        templates.deactivateTemplate(templateId);
    }

    /// @notice Cannot activate/deactivate non-existent template
    function testRevert_activateTemplate_NotFound() public {
        bytes32 fakeId = keccak256("fake");
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Types.TemplateNotFound.selector, fakeId));
        templates.activateTemplate(fakeId);
    }

    /// @notice Unauthorized caller cannot deactivate
    function testRevert_deactivateTemplate_Unauthorized() public {
        bytes32 templateId = _createRPSTemplate();
        vm.prank(stranger);
        vm.expectRevert();
        templates.deactivateTemplate(templateId);
    }

    // ========================================================================
    // View functions
    // ========================================================================

    /// @notice getTemplate returns correct data for existing template
    function test_getTemplate_Exists() public {
        bytes32 templateId = _createRPSTemplate();
        Types.Template memory t = templates.getTemplate(templateId);
        assertEq(t.id, templateId);
    }

    /// @notice getTemplate reverts for non-existent template
    function testRevert_getTemplate_NotFound() public {
        bytes32 fakeId = keccak256("nonexistent");
        vm.expectRevert(abi.encodeWithSelector(Types.TemplateNotFound.selector, fakeId));
        templates.getTemplate(fakeId);
    }

    /// @notice getActiveTemplates filters out deactivated templates
    function test_getActiveTemplates_Filters() public {
        bytes32 id1 = _createRPSTemplate();

        vm.prank(admin);
        bytes32 id2 = templates.createTemplate(
            "RPS Lobby 2",
            Types.ContractType.RPS,
            _encodeConditions(10e18, 100e18, 1, 15),
            _encodeRewardRules(true, 95),
            Types.PaymentType.IXFreePoint,
            FEE_RATE_BPS,
            Types.ChainRecordPolicy.Optional,
            bytes32(0)
        );

        // Deactivate first template
        vm.prank(admin);
        templates.deactivateTemplate(id1);

        Types.Template[] memory active = templates.getActiveTemplates();
        assertEq(active.length, 1, "Only one active template should remain");
        assertEq(active[0].id, id2);
    }

    /// @notice getTemplateCount returns correct count
    function test_getTemplateCount() public {
        assertEq(templates.getTemplateCount(), 0);
        _createRPSTemplate();
        assertEq(templates.getTemplateCount(), 1);
    }

    // ========================================================================
    // Fuzz tests
    // ========================================================================

    /// @notice Fuzz: fee rate must be in valid range [0, 5000]
    function testFuzz_createTemplate_FeeRateBoundaries(uint16 feeRate) public {
        if (feeRate > 5000) {
            vm.prank(admin);
            vm.expectRevert(abi.encodeWithSelector(Types.InvalidFeeRate.selector, feeRate));
            templates.createTemplate(
                string(abi.encodePacked("Fuzz Template ", vm.toString(feeRate))),
                Types.ContractType.RPS,
                _encodeConditions(10e18, 100e18, 1, 15),
                _encodeRewardRules(true, 95),
                Types.PaymentType.IXFreePoint,
                feeRate,
                Types.ChainRecordPolicy.Optional,
                bytes32(0)
            );
        } else {
            vm.prank(admin);
            bytes32 templateId = templates.createTemplate(
                string(abi.encodePacked("Fuzz Template ", vm.toString(feeRate))),
                Types.ContractType.RPS,
                _encodeConditions(10e18, 100e18, 1, 15),
                _encodeRewardRules(true, 95),
                Types.PaymentType.IXFreePoint,
                feeRate,
                Types.ChainRecordPolicy.Optional,
                bytes32(0)
            );
            assertEq(templates.getTemplateFeeRate(templateId), feeRate);
        }
    }
}
