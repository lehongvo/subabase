// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Types} from "./Types.sol";

/// @title FeeCalculator -- Pure library for basis-point fee arithmetic
/// @notice Calculates winner payouts, platform fees, and draw refunds for the IX Metaverse
///         Contract System. All amounts use uint128 to match the Settlement struct packing.
/// @dev All functions are pure (no state reads/writes). Uses basis points (bps) where
///      10000 bps = 100%. Maximum fee rate is 5000 bps (50%) to prevent abusive templates.
///
///      Rounding strategy: fees are rounded DOWN (truncated) in favor of the winner.
///      Any dust from integer division in draw refunds is silently absorbed (not redistributed).
///
///      Example: totalEscrow=100, feeRateBps=300 (3%)
///        feeAmount    = 100 * 300 / 10000 = 3
///        winnerAmount = 100 - 3 = 97
library FeeCalculator {

    /// @notice Maximum allowed fee rate: 5000 bps = 50%
    /// @dev Templates with fee_rate above this value must be rejected at creation time
    uint16 constant MAX_FEE_RATE = 5000;

    /// @notice Basis points denominator (10000 = 100%)
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @notice Calculate the winner payout and platform fee from total escrow
    /// @dev Fee is calculated first (rounded down), then winner gets the remainder.
    ///      This ensures no tokens are created out of thin air (winnerAmount + feeAmount == totalEscrow).
    ///
    ///      Edge cases:
    ///      - feeRateBps == 0: feeAmount = 0, winnerAmount = totalEscrow (no platform fee)
    ///      - feeRateBps == MAX_FEE_RATE (5000): feeAmount = totalEscrow/2, winnerAmount = totalEscrow - feeAmount
    ///      - totalEscrow == 0: reverts with Types.InvalidAmount()
    ///      - feeRateBps > MAX_FEE_RATE: reverts with Types.InvalidFeeRate(feeRateBps)
    ///
    /// @param totalEscrow The total escrowed amount from all parties (sum of all escrow deposits)
    /// @param feeRateBps Fee rate in basis points (0-5000)
    /// @return winnerAmount Amount to transfer to the winner (totalEscrow - feeAmount)
    /// @return feeAmount Amount to transfer to the treasury as platform fee
    function calculateFee(
        uint128 totalEscrow,
        uint16 feeRateBps
    ) internal pure returns (uint128 winnerAmount, uint128 feeAmount) {
        if (totalEscrow == 0) revert Types.InvalidAmount();
        if (feeRateBps > MAX_FEE_RATE) revert Types.InvalidFeeRate(feeRateBps);

        // Fee is rounded down (truncated), favoring the winner
        feeAmount = uint128((uint256(totalEscrow) * uint256(feeRateBps)) / BPS_DENOMINATOR);
        // Winner gets the exact remainder -- no dust is lost
        winnerAmount = totalEscrow - feeAmount;
    }

    /// @notice Calculate the per-party refund amount for a draw outcome
    /// @dev Divides total escrow equally among all parties. Any remainder (dust) from
    ///      integer division is silently absorbed and remains in the contract.
    ///
    ///      Example: totalEscrow=101, partyCount=2 -> refundPerParty=50, dust=1
    ///
    ///      Edge cases:
    ///      - totalEscrow == 0: reverts with Types.InvalidAmount()
    ///      - partyCount == 0: reverts with Types.InvalidAmount()
    ///
    /// @param totalEscrow The total escrowed amount from all parties
    /// @param partyCount Number of parties to split the refund among
    /// @return refundPerParty The refund amount each party receives
    function calculateDrawRefund(
        uint128 totalEscrow,
        uint8 partyCount
    ) internal pure returns (uint128 refundPerParty) {
        if (totalEscrow == 0) revert Types.InvalidAmount();
        if (partyCount == 0) revert Types.InvalidAmount();

        refundPerParty = uint128(uint256(totalEscrow) / uint256(partyCount));
    }
}
