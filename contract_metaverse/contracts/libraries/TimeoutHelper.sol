// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title TimeoutHelper -- Utility library for consent timeout and deadline management
/// @notice Provides deadline calculation and timeout checking for the IX Metaverse
///         Contract System's consent period. After a contract result is reported,
///         parties have a limited time window to consent or raise a dispute.
///         If the timeout elapses with no dispute, auto-consent is triggered.
/// @dev Contains both pure and view functions:
///      - `calculateDeadline` is view (reads block.timestamp)
///      - `isTimedOut` is view (reads block.timestamp)
///
///      A deadline of 0 means "never expires" (infinite timeout). This is used when
///      the template's timeoutSeconds is set to 0, indicating no automatic consent.
///
///      Example flow:
///      1. Result reported at block.timestamp = T
///      2. deadline = calculateDeadline(15) = T + 15
///      3. At block.timestamp = T + 16: isTimedOut(deadline) = true -> auto-consent
library TimeoutHelper {

    /// @notice Check if a deadline has been exceeded
    /// @dev Returns true if the current block timestamp is strictly greater than the deadline
    ///      AND the deadline is not zero. A deadline of 0 means "never expires".
    ///
    ///      Edge cases:
    ///      - deadline == 0: always returns false (never times out)
    ///      - block.timestamp == deadline: returns false (not yet timed out, must be strictly past)
    ///      - block.timestamp > deadline: returns true
    ///
    /// @param deadline The timestamp at which the timeout occurs (0 = never expires)
    /// @return timedOut True if the deadline has passed
    function isTimedOut(uint256 deadline) internal view returns (bool timedOut) {
        // deadline of 0 means "no timeout" (never expires)
        if (deadline == 0) return false;
        return block.timestamp > deadline;
    }

    /// @notice Calculate a future deadline from a timeout duration
    /// @dev Adds `timeoutSeconds` to the current `block.timestamp`. If `timeoutSeconds` is 0,
    ///      returns 0 to indicate "no deadline" (never expires).
    ///
    ///      Edge cases:
    ///      - timeoutSeconds == 0: returns 0 (no deadline / never expires)
    ///      - timeoutSeconds > 0: returns block.timestamp + timeoutSeconds
    ///
    ///      Note: Solidity 0.8.27 has built-in overflow protection, so adding a large
    ///      timeoutSeconds to block.timestamp will revert on overflow rather than wrapping.
    ///
    /// @param timeoutSeconds Duration in seconds until the deadline (0 = no deadline)
    /// @return deadline The calculated deadline timestamp (0 if timeoutSeconds is 0)
    function calculateDeadline(uint256 timeoutSeconds) internal view returns (uint256 deadline) {
        if (timeoutSeconds == 0) return 0;
        return block.timestamp + timeoutSeconds;
    }
}
