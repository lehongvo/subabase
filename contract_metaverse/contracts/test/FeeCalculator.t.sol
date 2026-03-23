// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {FeeCalculator} from "../libraries/FeeCalculator.sol";
import {Types} from "../libraries/Types.sol";

/// @title FeeCalculatorTest -- Tests for fee calculation library
contract FeeCalculatorTest is Test {
    // ========================================================================
    // calculateFee
    // ========================================================================

    /// @notice 3% fee: 100e18 totalEscrow -> 97e18 winner, 3e18 fee
    function test_calculateFee_ThreePercent() public pure {
        (uint128 winnerAmount, uint128 feeAmount) = FeeCalculator.calculateFee(100e18, 300);
        assertEq(winnerAmount, 97e18, "Winner should get 97e18");
        assertEq(feeAmount, 3e18, "Fee should be 3e18");
    }

    /// @notice 0% fee: winner gets everything
    function test_calculateFee_ZeroPercent() public pure {
        (uint128 winnerAmount, uint128 feeAmount) = FeeCalculator.calculateFee(100e18, 0);
        assertEq(winnerAmount, 100e18, "Winner should get full amount");
        assertEq(feeAmount, 0, "Fee should be zero");
    }

    /// @notice 50% fee (maximum allowed)
    function test_calculateFee_FiftyPercent() public pure {
        (uint128 winnerAmount, uint128 feeAmount) = FeeCalculator.calculateFee(100e18, 5000);
        assertEq(winnerAmount, 50e18, "Winner should get 50e18");
        assertEq(feeAmount, 50e18, "Fee should be 50e18");
    }

    /// @notice Over 50% fee rate reverts
    function testRevert_calculateFee_OverFiftyPercent() public {
        vm.expectRevert(abi.encodeWithSelector(Types.InvalidFeeRate.selector, uint16(5001)));
        FeeCalculator.calculateFee(100e18, 5001);
    }

    /// @notice Zero totalEscrow reverts
    function testRevert_calculateFee_ZeroEscrow() public {
        vm.expectRevert(abi.encodeWithSelector(Types.InvalidAmount.selector));
        FeeCalculator.calculateFee(0, 300);
    }

    /// @notice winnerAmount + feeAmount always equals totalEscrow (invariant)
    function testFuzz_calculateFee_Invariant(uint128 totalEscrow, uint16 feeRate) public {
        totalEscrow = uint128(bound(uint256(totalEscrow), 1, type(uint128).max));
        feeRate = uint16(bound(uint256(feeRate), 0, 5000));

        (uint128 winnerAmount, uint128 feeAmount) = FeeCalculator.calculateFee(totalEscrow, feeRate);

        assertEq(
            uint256(winnerAmount) + uint256(feeAmount),
            uint256(totalEscrow),
            "Winner + fee must equal total escrow"
        );
    }

    /// @notice Fuzz: fee is always <= totalEscrow * feeRate / 10000 (rounded down)
    function testFuzz_calculateFee_FeeRoundedDown(uint128 totalEscrow, uint16 feeRate) public pure {
        totalEscrow = uint128(bound(uint256(totalEscrow), 1, type(uint128).max));
        feeRate = uint16(bound(uint256(feeRate), 0, 5000));

        (, uint128 feeAmount) = FeeCalculator.calculateFee(totalEscrow, feeRate);

        uint256 expectedFee = (uint256(totalEscrow) * uint256(feeRate)) / 10_000;
        assertEq(uint256(feeAmount), expectedFee, "Fee should be exact truncated result");
    }

    // ========================================================================
    // calculateDrawRefund
    // ========================================================================

    /// @notice Draw refund splits equally
    function test_calculateDrawRefund_EqualSplit() public pure {
        uint128 refund = FeeCalculator.calculateDrawRefund(100e18, 2);
        assertEq(refund, 50e18, "Each party should get 50e18");
    }

    /// @notice Draw refund with odd amount: dust absorbed
    function test_calculateDrawRefund_DustAbsorbed() public pure {
        uint128 refund = FeeCalculator.calculateDrawRefund(101, 2);
        assertEq(refund, 50, "Dust of 1 is absorbed");
    }

    /// @notice Draw refund reverts with zero escrow
    function testRevert_calculateDrawRefund_ZeroEscrow() public {
        vm.expectRevert(abi.encodeWithSelector(Types.InvalidAmount.selector));
        FeeCalculator.calculateDrawRefund(0, 2);
    }

    /// @notice Draw refund reverts with zero party count
    function testRevert_calculateDrawRefund_ZeroPartyCount() public {
        vm.expectRevert(abi.encodeWithSelector(Types.InvalidAmount.selector));
        FeeCalculator.calculateDrawRefund(100e18, 0);
    }
}
