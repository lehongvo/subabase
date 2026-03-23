// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TestSetup} from "./helpers/TestSetup.sol";
import {Types} from "../libraries/Types.sol";
import {IContractParties} from "../interfaces/IContractParties.sol";

/// @title ContractPartiesTest -- Tests for party joining, escrow operations, and views
contract ContractPartiesTest is TestSetup {
    bytes32 internal templateId;
    bytes32 internal instanceId;

    function setUp() public override {
        super.setUp();
        templateId = _createRPSTemplate();
        instanceId = _createInstance(templateId);
    }

    // ========================================================================
    // joinContract — Happy path
    // ========================================================================

    /// @notice First party (alice) can join as challenger
    function test_joinContract_FirstParty() public {
        _aliceJoins(instanceId);

        assertEq(parties.getPartyCount(instanceId), 1);
        assertTrue(parties.hasJoined(instanceId, alice));
        assertEq(token.balanceOf(alice), MINT_AMOUNT - ESCROW_AMOUNT);
    }

    /// @notice Second party (bob) can join as opponent
    function test_joinContract_SecondParty() public {
        _aliceJoins(instanceId);
        _bobJoins(instanceId);

        assertEq(parties.getPartyCount(instanceId), 2);
        assertTrue(parties.hasJoined(instanceId, bob));
    }

    /// @notice joinContract emits PartyJoined event
    function test_joinContract_EmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IContractParties.PartyJoined(
            instanceId,
            alice,
            CHALLENGER_ROLE,
            ESCROW_AMOUNT,
            Types.PointType.IXFreePoint,
            uint48(block.timestamp)
        );
        parties.joinContract(
            instanceId,
            CHALLENGER_ROLE,
            ESCROW_AMOUNT,
            Types.PointType.IXFreePoint
        );
    }

    /// @notice Token balance is correctly transferred to parties contract on join
    function test_joinContract_TokenTransferred() public {
        uint256 partiesBalanceBefore = token.balanceOf(address(parties));
        _aliceJoins(instanceId);
        assertEq(token.balanceOf(address(parties)), partiesBalanceBefore + ESCROW_AMOUNT);
    }

    // ========================================================================
    // joinContract — Revert cases
    // ========================================================================

    /// @notice Cannot join the same contract twice
    function testRevert_joinContract_AlreadyJoined() public {
        _aliceJoins(instanceId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Types.AlreadyJoined.selector, instanceId, alice));
        parties.joinContract(instanceId, OPPONENT_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
    }

    /// @notice Cannot join when instance is not in Created status
    function testRevert_joinContract_InvalidStatus() public {
        _aliceJoins(instanceId);
        _bobJoins(instanceId);
        _activate(instanceId);

        // New user tries to join Active instance
        address charlie = makeAddr("charlie");
        token.mint(charlie, MINT_AMOUNT);
        vm.prank(charlie);
        token.approve(address(parties), type(uint256).max);

        vm.prank(charlie);
        vm.expectRevert(
            abi.encodeWithSelector(Types.InvalidState.selector, instanceId, Types.ContractStatus.Active)
        );
        parties.joinContract(instanceId, keccak256("spectator"), ESCROW_AMOUNT, Types.PointType.IXFreePoint);
    }

    /// @notice Cannot join with bet below template minimum
    function testRevert_joinContract_BetBelowMin() public {
        uint128 tooLow = 5e18; // min is 10e18
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Types.BetOutOfRange.selector, tooLow, uint128(10e18), uint128(100e18))
        );
        parties.joinContract(instanceId, CHALLENGER_ROLE, tooLow, Types.PointType.IXFreePoint);
    }

    /// @notice Cannot join with bet above template maximum
    function testRevert_joinContract_BetAboveMax() public {
        uint128 tooHigh = 101e18; // max is 100e18
        // Mint extra tokens
        token.mint(alice, 200e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Types.BetOutOfRange.selector, tooHigh, uint128(10e18), uint128(100e18))
        );
        parties.joinContract(instanceId, CHALLENGER_ROLE, tooHigh, Types.PointType.IXFreePoint);
    }

    /// @notice Cannot join with zero escrow amount
    function testRevert_joinContract_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Types.InvalidAmount.selector));
        parties.joinContract(instanceId, CHALLENGER_ROLE, 0, Types.PointType.IXFreePoint);
    }

    /// @notice Cannot join with insufficient token balance (transfer reverts)
    function testRevert_joinContract_InsufficientBalance() public {
        address poorUser = makeAddr("poor");
        // No tokens minted for poorUser

        vm.prank(poorUser);
        token.approve(address(parties), type(uint256).max);

        vm.prank(poorUser);
        vm.expectRevert(); // SafeERC20 transfer will fail
        parties.joinContract(instanceId, CHALLENGER_ROLE, ESCROW_AMOUNT, Types.PointType.IXFreePoint);
    }

    // ========================================================================
    // releaseEscrow
    // ========================================================================

    /// @notice releaseEscrow transfers tokens to recipient
    function test_releaseEscrow_Success() public {
        _aliceJoins(instanceId);
        _bobJoins(instanceId);

        uint256 bobBalBefore = token.balanceOf(bob);

        // Release to bob (simulating settlement)
        vm.prank(address(settlements));
        parties.releaseEscrow(instanceId, bob, 97e18);

        assertEq(token.balanceOf(bob), bobBalBefore + 97e18);
    }

    /// @notice Unauthorized caller cannot release escrow
    function testRevert_releaseEscrow_Unauthorized() public {
        _aliceJoins(instanceId);
        _bobJoins(instanceId);

        vm.prank(stranger);
        vm.expectRevert();
        parties.releaseEscrow(instanceId, bob, 50e18);
    }

    // ========================================================================
    // refundEscrow
    // ========================================================================

    /// @notice refundEscrow returns tokens to all parties
    function test_refundEscrow_Success() public {
        _aliceJoins(instanceId);
        _bobJoins(instanceId);

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);

        vm.prank(address(settlements));
        parties.refundEscrow(instanceId);

        assertEq(token.balanceOf(alice), aliceBefore + ESCROW_AMOUNT);
        assertEq(token.balanceOf(bob), bobBefore + ESCROW_AMOUNT);
    }

    // ========================================================================
    // View functions
    // ========================================================================

    /// @notice getParties returns all joined parties
    function test_getParties_ReturnsAll() public {
        _aliceJoins(instanceId);
        _bobJoins(instanceId);

        Types.Party[] memory ps = parties.getParties(instanceId);
        assertEq(ps.length, 2);
    }

    /// @notice getPartyCount returns correct count
    function test_getPartyCount() public {
        assertEq(parties.getPartyCount(instanceId), 0);
        _aliceJoins(instanceId);
        assertEq(parties.getPartyCount(instanceId), 1);
        _bobJoins(instanceId);
        assertEq(parties.getPartyCount(instanceId), 2);
    }

    /// @notice getTotalEscrow sums all party escrow amounts
    function test_getTotalEscrow() public {
        _aliceJoins(instanceId);
        _bobJoins(instanceId);

        uint128 total = parties.getTotalEscrow(instanceId);
        assertEq(total, ESCROW_AMOUNT * 2);
    }

    /// @notice getParty returns correct data for a specific party
    function test_getParty_Success() public {
        _aliceJoins(instanceId);
        Types.Party memory p = parties.getParty(instanceId, alice);
        assertEq(p.userId, alice);
        assertEq(p.escrowAmount, ESCROW_AMOUNT);
        assertEq(p.role, CHALLENGER_ROLE);
    }

    /// @notice getParty reverts for non-party
    function testRevert_getParty_NotAParty() public {
        vm.expectRevert(abi.encodeWithSelector(Types.NotAParty.selector, instanceId, stranger));
        parties.getParty(instanceId, stranger);
    }

    // ========================================================================
    // Fuzz test
    // ========================================================================

    /// @notice Fuzz: valid escrow amounts within template bounds are accepted
    function testFuzz_joinContract_ValidAmounts(uint128 amount) public {
        // Bound amount to template range [10e18, 100e18]
        amount = uint128(bound(uint256(amount), 10e18, 100e18));

        // Mint enough tokens
        token.mint(alice, amount);

        // Create fresh instance for this fuzz run
        vm.prank(admin);
        bytes32 fuzzInstanceId = instances.createInstance(
            templateId,
            abi.encode("fuzz", "session")
        );

        vm.prank(alice);
        parties.joinContract(fuzzInstanceId, CHALLENGER_ROLE, amount, Types.PointType.IXFreePoint);

        assertEq(parties.getTotalEscrow(fuzzInstanceId), amount);
    }
}
