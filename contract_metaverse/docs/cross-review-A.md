# Cross-Review Report A: Agent 4 (Results, Consents, Settlements) & Agent 5 (Libraries, Security)

| Item | Details |
| --- | --- |
| Reviewer | Senior Solidity Code Reviewer |
| Date | 2026-03-23 |
| Scope | ContractResults, ContractConsents, ContractSettlements, MockIXToken, AccessRoles, EmergencyStop, FeeCalculator, StateValidator, TimeoutHelper, Types |

---

## Summary

Total issues found: **14**

| Severity | Count |
| --- | --- |
| CRITICAL | 3 |
| HIGH | 4 |
| MEDIUM | 4 |
| LOW | 3 |

---

## Issues

### [CRITICAL-1] ContractSettlements uses non-upgradeable ReentrancyGuard with upgradeable proxy pattern

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractSettlements.sol`
- **Line**: 6, 30
- **Category**: Security
- **Description**: `ContractSettlements` imports and inherits `ReentrancyGuard` from `@openzeppelin/contracts/utils/ReentrancyGuard.sol` (non-upgradeable). The architecture design specifies `ReentrancyGuardUpgradeable` for contracts deployed behind `TransparentUpgradeableProxy`. The non-upgradeable version uses a constructor to set the initial `_status` value, which is never called through a proxy. This means `_status` is initialized to 0 instead of the expected `_NOT_ENTERED` value (1), which in OZ v5 could cause all `nonReentrant` calls to revert or behave incorrectly.
- **Impact**: All settlement functions (`settleContract`, `refundContract`) may revert or have no reentrancy protection depending on OZ version internals.
- **Recommendation**: Replace `ReentrancyGuard` with `ReentrancyGuardUpgradeable` and call `__ReentrancyGuard_init()` in `initialize()`.

### [CRITICAL-2] ContractSettlements does not use FeeCalculator library

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractSettlements.sol`
- **Line**: 207
- **Category**: Correctness / Cross-Contract Consistency
- **Description**: The architecture design mandates that `ContractSettlements` uses `FeeCalculator` library for fee math. Instead, the contract performs inline fee calculation: `uint128 feeAmount = uint128((uint256(totalEscrow) * uint256(feeRateBps)) / 10000)`. While the math is correct for now, it bypasses the library's `MAX_FEE_RATE` validation (5000 bps cap) and the `totalEscrow == 0` check. If an admin sets a fee rate above 50%, the library would reject it but the inline code would silently compute an excessive fee.
- **Impact**: Fee rate safety bounds not enforced during settlement. A malicious or misconfigured fee rate > 50% could drain winner funds. Duplicate logic creates maintenance risk.
- **Recommendation**: Import and use `FeeCalculator.calculateFee(totalEscrow, feeRateBps)`.

### [CRITICAL-3] ContractConsents does not initialize _templatesContract in initialize()

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractConsents.sol`
- **Line**: 81-99
- **Category**: Correctness
- **Description**: The `initialize()` function accepts `instancesContract` and `partiesContract` but not `templatesContract`. The `_templatesContract` is declared as state (line 60) and used in `_getTimeoutSeconds()` (line 355), but it is only settable via `setTemplatesContract()` which must be called separately after deployment. If not called, the fallback 300-second timeout is used. More importantly, a gap between deployment and `setTemplatesContract()` call means consent deadlines are computed with wrong timeouts.
- **Impact**: Consent timeouts default to 300 seconds instead of the template-defined value (e.g., 15 seconds for RPS) if admin forgets to call `setTemplatesContract()`. This could delay or block settlements.
- **Recommendation**: Add `templatesContract` parameter to `initialize()`.

### [HIGH-1] AccessRoles library constants not used by core contracts

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/security/AccessRoles.sol`
- **Line**: 39-51
- **Category**: Cross-Contract Consistency
- **Description**: `AccessRoles.sol` defines centralized role constants (`ADMIN_ROLE`, `SERVER_ROLE`, `SETTLER_ROLE`, `ORACLE_ROLE`) as a library. However, none of the core contracts (`ContractResults`, `ContractConsents`, `ContractSettlements`) import or use `AccessRoles`. Instead, each contract re-declares role constants inline (e.g., `bytes32 public constant SERVER_ROLE = keccak256("SERVER_ROLE")`). This defeats the purpose of the centralized library.
- **Impact**: If role strings are changed in `AccessRoles` but not in the core contracts, role mismatches would create access control failures. Maintenance burden from duplicate definitions.
- **Recommendation**: Import `AccessRoles` and reference `AccessRoles.SERVER_ROLE` etc., or remove the library if inline constants are the chosen pattern.

### [HIGH-2] EmergencyStop abstract contract not used by any core contract

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/security/EmergencyStop.sol`
- **Line**: All
- **Category**: Cross-Contract Consistency
- **Description**: `EmergencyStop` provides granular per-contract pause and emergency fund recovery with timelock. However, none of the reviewed contracts (`ContractResults`, `ContractConsents`, `ContractSettlements`) inherit from it. They all use OZ's `PausableUpgradeable` instead, which only provides a single global pause. The per-contract pause and emergency recovery features specified in the architecture are not available.
- **Impact**: No per-contract-instance pause granularity. No timelocked emergency fund recovery. The system can only do coarse-grained global pause.
- **Recommendation**: This is an integration task. When integrating `EmergencyStop`, contracts should inherit it and use `whenOperational(contractId)` modifier. For now, document this as a known gap to be addressed during integration.

### [HIGH-3] ContractSettlements._paymentToken declared but never used

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractSettlements.sol`
- **Line**: 72
- **Category**: Quality / Correctness
- **Description**: The `_paymentToken` state variable (IERC20) is declared, initialized in `initialize()`, and has a setter `setPaymentToken()`, but is never actually used in any settlement function. All token transfers go through `_partiesContract.releaseEscrow()` and `_partiesContract.refundEscrow()`, which handle the actual ERC-20 transfers. This is dead code that wastes a storage slot and confuses readers.
- **Impact**: Unused storage slot wastes gas during initialization. Misleading API surface (setPaymentToken exists but has no effect).
- **Recommendation**: Remove `_paymentToken`, its initialization, and `setPaymentToken()` since token operations are delegated to ContractParties.

### [HIGH-4] Unused variable warning at ContractSettlements.sol line 332 (pointType)

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractSettlements.sol`
- **Line**: 332
- **Category**: Quality
- **Description**: `Types.PointType pointType` is assigned on line 332 inside `refundContract()` but is never used. The per-party loop on line 348 correctly uses `party.escrowType` instead, making the outer `pointType` variable unused.
- **Impact**: Compiler warning. Wastes a small amount of gas reading the value.
- **Recommendation**: Remove the unused variable declaration.

### [MEDIUM-1] ContractConsents.autoConsent does not check instance status

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractConsents.sol`
- **Line**: 186-228
- **Category**: Correctness
- **Description**: `autoConsent()` does not verify the instance status is `Completed` or `Resolved` before recording auto-consent. While `submitConsent()` does check status (line 123-126), `autoConsent()` skips this check. This means auto-consent could be applied even after the contract has been disputed or settled.
- **Impact**: Consent count could be incremented on already-disputed or settled contracts, corrupting consent tracking.
- **Recommendation**: Add instance status validation: require status == Completed or Resolved.

### [MEDIUM-2] ContractConsents.submitConsent re-reads instance status in Interactions section

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractConsents.sol`
- **Line**: 174
- **Category**: Gas
- **Description**: In the dispute branch (line 174), `submitConsent()` calls `_instancesContract.getInstanceStatus(instanceId)` a second time to check if the status is still `Completed` before calling `disputeInstance()`. The status was already read at line 123. While this is defensive against a race condition from the external call to `_instancesContract`, the first read already confirmed `Completed` status and no state-changing calls happen between lines 123 and 174 that could change it.
- **Impact**: Wastes gas on a redundant external call (~2600 gas for SLOAD + call overhead).
- **Recommendation**: Cache the status from the first read and use it. The re-read is only necessary if an external call between the two reads could change the status, which is not the case here.

### [MEDIUM-3] FeeCalculator.calculateDrawRefund not used by ContractSettlements.refundContract

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractSettlements.sol`, `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/libraries/FeeCalculator.sol`
- **Line**: ContractSettlements:335, FeeCalculator:67
- **Category**: Cross-Contract Consistency
- **Description**: `FeeCalculator` provides `calculateDrawRefund()` for computing per-party refund in draw scenarios. However, `ContractSettlements.refundContract()` manually iterates parties and refunds each party their exact `escrowAmount` (line 337: `party.escrowAmount`). This is actually correct behavior per requirements (each party gets their own deposit back, not an equal split), but it means `calculateDrawRefund()` is dead code that computes something different (equal split of total).
- **Impact**: `calculateDrawRefund()` is misleading dead code. It assumes equal splits, which contradicts the requirement that each party gets back their own deposit.
- **Recommendation**: Either remove `calculateDrawRefund()` from the library (since refund is per-party, not split), or document that it is intended for future tournament use where equal splits might apply.

### [MEDIUM-4] TimeoutHelper library not used by ContractConsents

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractConsents.sol`, `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/libraries/TimeoutHelper.sol`
- **Line**: ContractConsents:197, TimeoutHelper:all
- **Category**: Cross-Contract Consistency
- **Description**: `TimeoutHelper` provides `isTimedOut()` and `calculateDeadline()` utilities. `ContractConsents` implements its own inline timeout logic: `_consentDeadline[instanceId] = consentedAt + uint48(timeoutSeconds)` (line 158) and `block.timestamp < deadline` (line 197). The `TimeoutHelper.isTimedOut()` uses `block.timestamp > deadline` (strictly greater), while the inline code uses `block.timestamp < deadline` (strictly less, equivalent). However, a dedicated library exists and should be used for consistency.
- **Impact**: Duplicate logic. `TimeoutHelper` handles the `deadline == 0` edge case (never expires), while the inline code does not -- it would consider `deadline == 0` as always timed out since `block.timestamp > 0`.
- **Recommendation**: Use `TimeoutHelper.isTimedOut()` and `TimeoutHelper.calculateDeadline()` in ContractConsents.

### [LOW-1] StateValidator library not used by any reviewed contract

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/libraries/StateValidator.sol`
- **Line**: All
- **Category**: Cross-Contract Consistency
- **Description**: `StateValidator` provides `validateTransition()` for FSM enforcement. The reviewed contracts (`ContractResults`, `ContractConsents`, `ContractSettlements`) perform their own inline status checks. ContractInstances is the primary consumer, but the library is available for cross-contract validation which is not happening.
- **Impact**: Low impact. The inline checks are correct. The library mainly benefits ContractInstances.
- **Recommendation**: Acceptable as-is. The library is designed for ContractInstances use. Document that other contracts do point-checks rather than transition validation.

### [LOW-2] EmergencyStop.requestRecovery uses wrong error for zero-address check

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/security/EmergencyStop.sol`
- **Line**: 206
- **Category**: Quality
- **Description**: `requestRecovery()` checks `if (target == address(0)) revert InvalidRecoveryDelay()`. The error name `InvalidRecoveryDelay` is semantically wrong for a zero-address check.
- **Impact**: Misleading error message. Debugging difficulty.
- **Recommendation**: Add a proper error like `InvalidRecoveryTarget()` or reuse an existing zero-address error.

### [LOW-3] ContractResults.overrideResult reads old result data into memory unnecessarily

- **File**: `/Users/user/Desktop/mcc/subabase/contract_metaverse/contracts/ContractResults.sol`
- **Line**: 171
- **Category**: Gas
- **Description**: `bytes memory oldResultData = result.resultData` copies the entire result data from storage to memory. This is only used for the `ResultOverridden` event emission. If result data is large, this is expensive.
- **Impact**: Higher gas cost for large result data. Minor issue since result data is typically small.
- **Recommendation**: Acceptable as-is since the event provides useful audit trail. Could optimize by emitting only a hash of old data if gas is a concern.

---

## Fixes Applied

1. **CRITICAL-1**: Changed `ReentrancyGuard` to `ReentrancyGuardUpgradeable` and added `__ReentrancyGuard_init()` call in ContractSettlements.
2. **CRITICAL-2**: Imported and used `FeeCalculator.calculateFee()` in ContractSettlements.
3. **CRITICAL-3**: Added `templatesContract` parameter to ContractConsents.initialize().
4. **HIGH-3 + HIGH-4**: Removed unused `_paymentToken` and `setPaymentToken()`, removed unused `pointType` variable in `refundContract()`.
5. **MEDIUM-1**: Added instance status check in `autoConsent()`.
6. **MEDIUM-2**: Cached status to avoid redundant external call in `submitConsent()`.
7. **LOW-2**: Fixed wrong error type in EmergencyStop.requestRecovery().

Items marked as cross-contract consistency gaps (HIGH-1, HIGH-2, MEDIUM-3, MEDIUM-4, LOW-1) are documented but not fixed, as they require broader architectural decisions about library adoption vs inline patterns.
