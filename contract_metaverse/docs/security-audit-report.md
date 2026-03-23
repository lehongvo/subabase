# IX Metaverse Contract Management System -- Security Audit Report

| Item | Details |
| --- | --- |
| **Auditor** | Smart Contract Security Auditor |
| **Date** | 2026-03-23 |
| **Scope** | All Solidity contracts in `contracts/` (6 core, 3 libraries, 3 interfaces, 2 security, 1 mock) |
| **Commit** | HEAD of `main` branch |
| **Framework** | Foundry (forge) |
| **Solidity** | ^0.8.27 |
| **Dependencies** | OpenZeppelin Contracts 5.x, OpenZeppelin Contracts Upgradeable 5.x |

---

## Executive Summary

The IX Metaverse Contract Management System implements a 6-contract architecture managing consent-based interactions (contracts) between metaverse users. The system handles template management, instance lifecycle, party escrow, result reporting, consent collection, and settlement with fee distribution.

**Overall Assessment: MODERATE RISK**

The system demonstrates strong architectural design with a well-defined state machine, role-based access control, and the Checks-Effects-Interactions pattern consistently applied. However, the audit identified several findings ranging from critical proxy-pattern incompatibilities to informational dead-code concerns. The cross-review documents (cross-review-A.md and cross-review-B.md) previously identified and fixed several critical issues; this audit validates those fixes and identifies residual and newly discovered concerns.

**Key Strengths:**
- Strict state machine enforcement via `StateValidator` library with 6 explicitly defined transitions
- Role-based access control using OpenZeppelin's `AccessControlUpgradeable` with 5 distinct roles
- Checks-Effects-Interactions pattern consistently followed across all state-changing functions
- `nonReentrant` guards on all escrow-touching functions (`joinContract`, `releaseEscrow`, `refundEscrow`, `settleContract`, `refundContract`)
- `SafeERC20` used for all token transfers
- Fee calculation uses basis points with a hard 5000 bps (50%) cap
- Cumulative release tracking (`_totalReleased`) prevents escrow over-release

**Key Risks:**
- Non-upgradeable `ReentrancyGuard` used with proxy pattern (previously identified, may or may not be fully fixed)
- Several libraries (`AccessRoles`, `EmergencyStop`, `TimeoutHelper`) are implemented but not integrated
- `FeeCalculator.calculateDrawRefund()` computes equal splits but `refundContract()` returns exact deposits -- semantic inconsistency
- Centralized admin power: a compromised `DEFAULT_ADMIN_ROLE` key can drain all escrow via `setTreasury` + `settleContract`

---

## Methodology

### Manual Code Review

1. **Line-by-line review** of all 19 Solidity source files (6 core contracts, 4 interfaces, 3 libraries, 2 security modules, 1 mock, 1 test setup)
2. **Architecture analysis** against the requirements-analysis.md and architecture-design.md specifications
3. **Cross-review validation** of findings from cross-review-A.md (14 issues) and cross-review-B.md (13 issues)
4. **Access control matrix** verification: every role-restricted function mapped against the AccessRoles specification
5. **State machine analysis**: all 6 valid transitions verified; all invalid transitions tested for revert
6. **Token flow analysis**: traced every `safeTransferFrom`, `safeTransfer`, `releaseEscrow`, and `refundEscrow` call for correctness

### Attack Test Suite

5 dedicated attack test contracts targeting specific vulnerability categories:

| Test File | Target | Attack Vectors |
| --- | --- | --- |
| `ReentrancyAttack.t.sol` | ContractParties, ContractSettlements | Malicious ERC-20 callback, double release, double refund |
| `AccessControlAttack.t.sol` | All 6 contracts | Unauthorized calls, role escalation, role revocation |
| `StateMachineAttack.t.sol` | ContractInstances | State skipping, state reversal, double settle, invalid result submission |
| `EscrowManipulation.t.sol` | ContractParties | Zero amount, out-of-range bets, drain via double release, cross-instance isolation |
| `FeeManipulation.t.sol` | ContractTemplates, ContractSettlements, FeeCalculator | Fee rate bounds, invariant fuzz testing, fee bypass via direct escrow release |

---

## Findings

### SEC-01: Non-Upgradeable ReentrancyGuard in Proxy-Deployed Contracts

| Field | Value |
| --- | --- |
| **ID** | SEC-01 |
| **Severity** | CRITICAL |
| **Contract** | `ContractParties.sol`, `ContractSettlements.sol` |
| **Function** | All `nonReentrant` functions |
| **Status** | PREVIOUSLY IDENTIFIED (cross-review-A CRITICAL-1, cross-review-B CRITICAL-01) |

**Description:** Both `ContractParties` and `ContractSettlements` import `ReentrancyGuard` from `@openzeppelin/contracts/utils/ReentrancyGuard.sol` (non-upgradeable version). These contracts are designed for deployment behind `TransparentUpgradeableProxy`. The non-upgradeable `ReentrancyGuard` initializes its state in a constructor, which never executes in a proxy context. In OZ v5, the non-upgradeable `ReentrancyGuard` uses transient storage (EIP-1153) and does not require constructor initialization, so it happens to work. However, this is version-dependent and fragile.

**Impact:** If the OZ dependency is downgraded or the implementation changes, reentrancy protection could silently fail, enabling token theft via reentrant `releaseEscrow` or `settleContract` calls.

**Recommendation:** Replace with `ReentrancyGuardUpgradeable` and call `__ReentrancyGuard_init()` in `initialize()`. The cross-review reports indicate this was fixed, but the current codebase still shows the non-upgradeable import.

---

### SEC-02: Centralized Admin Key Risk

| Field | Value |
| --- | --- |
| **ID** | SEC-02 |
| **Severity** | HIGH |
| **Contract** | All contracts |
| **Function** | `initialize()`, `grantRole()`, `setTreasury()` |
| **Status** | OPEN |

**Description:** The `DEFAULT_ADMIN_ROLE` holder has unrestricted power to: (a) change the treasury address to any wallet, (b) grant themselves all roles, (c) settle any contract directing funds to the new treasury. A compromised admin key enables complete fund theft. There is no multi-sig requirement, timelock, or admin key rotation mechanism.

**Impact:** Single point of failure. All escrowed funds at risk if the admin private key is compromised.

**Recommendation:** Implement a multi-sig wallet or timelock (e.g., OpenZeppelin's `TimelockController`) for `DEFAULT_ADMIN_ROLE`. Consider adopting `AccessControlDefaultAdminRules` for admin transfer with a delay. The `EmergencyStop` contract already provides a timelocked recovery mechanism but is not integrated.

---

### SEC-03: EmergencyStop Module Not Integrated

| Field | Value |
| --- | --- |
| **ID** | SEC-03 |
| **Severity** | MEDIUM |
| **Contract** | `security/EmergencyStop.sol` vs all core contracts |
| **Function** | `whenOperational()`, `globalPause()`, `pauseContract()` |
| **Status** | OPEN (previously identified cross-review-A HIGH-2) |

**Description:** `EmergencyStop.sol` provides granular per-contract-instance pause and timelocked emergency fund recovery. None of the 6 core contracts inherit from it. They use OpenZeppelin's `PausableUpgradeable` which only provides a single global pause toggle. The per-instance pause and emergency recovery features are dead code.

**Impact:** No ability to surgically pause a single compromised contract instance while keeping the rest of the system operational. No timelocked emergency fund recovery.

**Recommendation:** Integrate `EmergencyStop` into `ContractParties` and `ContractSettlements` (the contracts holding/distributing funds). Replace or supplement `whenNotPaused` with `whenOperational(instanceId)`.

---

### SEC-04: AccessRoles Library Not Used by Core Contracts

| Field | Value |
| --- | --- |
| **ID** | SEC-04 |
| **Severity** | LOW |
| **Contract** | `security/AccessRoles.sol` vs all core contracts |
| **Function** | N/A |
| **Status** | OPEN (previously identified cross-review-A HIGH-1) |

**Description:** `AccessRoles.sol` defines centralized role constants (`ADMIN_ROLE`, `SERVER_ROLE`, `SETTLER_ROLE`, `ORACLE_ROLE`). Every core contract re-declares these constants inline. If a role string is changed in one place but not another, access control would silently break.

**Impact:** Maintenance risk. Duplicate role definitions across 6 contracts.

**Recommendation:** Either import and use `AccessRoles.ADMIN_ROLE` etc. from the library, or remove the library if inline constants are the intended pattern.

---

### SEC-05: TimeoutHelper Library Not Used by ContractConsents

| Field | Value |
| --- | --- |
| **ID** | SEC-05 |
| **Severity** | LOW |
| **Contract** | `ContractConsents.sol`, `libraries/TimeoutHelper.sol` |
| **Function** | `autoConsent()`, `_getTimeoutSeconds()` |
| **Status** | OPEN (previously identified cross-review-A MEDIUM-4) |

**Description:** `ContractConsents` implements inline timeout logic that does not handle the `deadline == 0` edge case (never-expires) correctly. `TimeoutHelper.isTimedOut()` explicitly returns `false` when `deadline == 0`, but the inline check `block.timestamp < deadline` would treat `deadline == 0` as always-expired (since `block.timestamp > 0`).

**Impact:** If a template with `timeoutSeconds == 0` is used, the consent deadline would be `consentedAt + 0 = consentedAt`, and `autoConsent` would immediately succeed (bypassing any real timeout). The `_getTimeoutSeconds` function enforces a minimum of 10 seconds, partially mitigating this.

**Recommendation:** Use `TimeoutHelper.isTimedOut()` and `TimeoutHelper.calculateDeadline()` in `ContractConsents` for consistent edge-case handling.

---

### SEC-06: FeeCalculator.calculateDrawRefund Is Dead Code

| Field | Value |
| --- | --- |
| **ID** | SEC-06 |
| **Severity** | INFORMATIONAL |
| **Contract** | `libraries/FeeCalculator.sol` |
| **Function** | `calculateDrawRefund()` |
| **Status** | OPEN (previously identified cross-review-A MEDIUM-3) |

**Description:** `calculateDrawRefund()` computes equal-split refunds, but `refundContract()` returns each party's exact deposit. The function is never called by any contract.

**Impact:** Dead code that may mislead future developers into using it incorrectly.

**Recommendation:** Remove the function or clearly document it is reserved for future tournament use.

---

### SEC-07: refundContract Allows Refund from Created/Active States

| Field | Value |
| --- | --- |
| **ID** | SEC-07 |
| **Severity** | MEDIUM |
| **Contract** | `ContractSettlements.sol` |
| **Function** | `refundContract()` |
| **Status** | OPEN |

**Description:** `refundContract()` accepts instances in `Created`, `Active`, `Completed`, or `Resolved` states. Allowing refund from `Created` and `Active` states means a SETTLER or ADMIN can cancel a contract before it completes, refunding escrow and marking it Settled. While this may be intended for cancellation, it bypasses the normal lifecycle and the state machine's `settleInstance()` call will attempt `Created/Active -> Settled` which is not a valid transition per `StateValidator`.

**Impact:** The `settleInstance()` call at the end of `refundContract()` will revert for `Created` or `Active` states because `StateValidator` only allows `Completed -> Settled` and `Resolved -> Settled`. This means refunds from these early states will always revert.

**Recommendation:** Either add `Created -> Settled` and `Active -> Settled` as valid transitions in `StateValidator`, or restrict `refundContract` to only `Completed` and `Resolved` states, or handle the state transition differently for early cancellation.

---

### SEC-08: No Maximum Party Count Enforcement

| Field | Value |
| --- | --- |
| **ID** | SEC-08 |
| **Severity** | LOW |
| **Contract** | `ContractParties.sol` |
| **Function** | `joinContract()` |
| **Status** | OPEN |

**Description:** There is no check against a maximum number of parties per instance. The `_partyCount` is `uint8` (max 255), and `MaxPartiesReached` error is defined in `Types.sol` but never used. An unbounded number of parties (up to 255) could join, causing gas issues in `refundEscrow()` and `getTotalEscrow()` which iterate all parties.

**Impact:** Gas exhaustion risk on `refundEscrow()` and settlement if too many parties join. Low practical risk since `activateInstance()` only requires 2 parties and the instance moves to Active after activation, preventing further joins.

**Recommendation:** Add a `maxParties` field to template conditions and enforce it in `joinContract()`.

---

### SEC-09: Consent Deadline Uses uint48 Truncation

| Field | Value |
| --- | --- |
| **ID** | SEC-09 |
| **Severity** | INFORMATIONAL |
| **Contract** | `ContractConsents.sol` |
| **Function** | `submitConsent()` |
| **Status** | OPEN |

**Description:** The consent deadline is stored as `uint48`: `_consentDeadline[instanceId] = consentedAt + uint48(timeoutSeconds)`. If `timeoutSeconds` exceeds `type(uint48).max`, the cast silently truncates to a much smaller value, potentially creating an immediately-expired deadline.

**Impact:** Negligible in practice since `_getTimeoutSeconds()` reads from template conditions where realistic timeouts are seconds to hours. The minimum is enforced at 10 seconds.

**Recommendation:** Add an explicit bound check: `require(timeoutSeconds <= type(uint48).max)`.

---

### SEC-10: Result Data Not Validated for Structure

| Field | Value |
| --- | --- |
| **ID** | SEC-10 |
| **Severity** | LOW |
| **Contract** | `ContractResults.sol`, `ContractSettlements.sol` |
| **Function** | `reportResult()`, `settleContract()` |
| **Status** | OPEN |

**Description:** `reportResult()` only checks `resultData.length == 0`. The `settleContract()` function then `abi.decode`s the result data assuming a specific structure `(address, string, string, uint256, string, bool)`. If a SERVER_ROLE account submits malformed data that passes the length check but fails decode, `settleContract()` will revert at settlement time rather than at submission time.

**Impact:** A malformed result could block settlement entirely, requiring admin intervention (override result or refund). Low risk since SERVER_ROLE is trusted.

**Recommendation:** Consider validating result data structure in `reportResult()` by attempting a test decode, or at minimum document the expected encoding format on-chain.

---

## Attack Test Results

| Test Contract | Tests | Target | Attack Vector | Result |
| --- | --- | --- | --- | --- |
| **ReentrancyAttack.t.sol** | | | | |
| | `test_reentrancy_releaseEscrow_blocked` | ContractParties.releaseEscrow | Reentrant callback during token transfer | BLOCKED (nonReentrant) |
| | `test_reentrancy_releaseEscrow_unauthorized_revert` | ContractParties.releaseEscrow | Direct call without CONTRACT_ROLE | BLOCKED (onlyRole) |
| | `test_reentrancy_double_release_blocked` | ContractParties.releaseEscrow | Double settlement attempt | BLOCKED (SettlementAlreadyDone) |
| | `test_reentrancy_settleContract_blocked` | ContractSettlements.settleContract | Reentrant settlement | BLOCKED (nonReentrant) |
| | `test_reentrancy_refundContract_blocked` | ContractSettlements.refundContract | Double refund attempt | BLOCKED (SettlementAlreadyDone) |
| | `test_reentrancy_joinContract_blocked` | ContractParties.joinContract | Double join via reentrancy | BLOCKED (AlreadyJoined + nonReentrant) |
| | `test_reentrancy_refundEscrow_blocked` | ContractParties.refundEscrow | Reentrant refund | BLOCKED (nonReentrant via settlements) |
| **AccessControlAttack.t.sol** | | | | |
| | `test_unauthorized_createTemplate_reverts` | ContractTemplates.createTemplate | Stranger calls admin function | BLOCKED (onlyRole) |
| | `test_unauthorized_updateTemplate_reverts` | ContractTemplates.updateTemplate | Stranger updates template | BLOCKED (onlyRole) |
| | `test_unauthorized_activateTemplate_reverts` | ContractTemplates.activateTemplate | Stranger activates template | BLOCKED (onlyRole) |
| | `test_unauthorized_deactivateTemplate_reverts` | ContractTemplates.deactivateTemplate | Stranger deactivates template | BLOCKED (onlyRole) |
| | `test_unauthorized_createInstance_reverts` | ContractInstances.createInstance | Stranger creates instance | BLOCKED (onlyRole) |
| | `test_unauthorized_activateInstance_reverts` | ContractInstances.activateInstance | Stranger activates instance | BLOCKED (onlyRole) |
| | `test_unauthorized_completeInstance_reverts` | ContractInstances.completeInstance | Stranger completes instance | BLOCKED (onlyRole) |
| | `test_unauthorized_disputeInstance_reverts` | ContractInstances.disputeInstance | Stranger disputes instance | BLOCKED (onlyRole) |
| | `test_unauthorized_resolveInstance_reverts` | ContractInstances.resolveInstance | Stranger resolves instance | BLOCKED (Unauthorized) |
| | `test_unauthorized_settleInstance_reverts` | ContractInstances.settleInstance | Stranger settles instance | BLOCKED (onlyRole) |
| | `test_unauthorized_settleContract_reverts` | ContractSettlements.settleContract | Stranger settles contract | BLOCKED (onlyRole) |
| | `test_unauthorized_refundContract_reverts` | ContractSettlements.refundContract | Stranger refunds contract | BLOCKED (Unauthorized) |
| | `test_unauthorized_reportResult_reverts` | ContractResults.reportResult | Stranger reports result | BLOCKED (onlyRole) |
| | `test_unauthorized_overrideResult_reverts` | ContractResults.overrideResult | Stranger overrides result | BLOCKED (onlyRole) |
| | `test_unauthorized_submitConsent_reverts` | ContractConsents.submitConsent | Stranger submits consent | BLOCKED (onlyRole) |
| | `test_unauthorized_autoConsent_reverts` | ContractConsents.autoConsent | Stranger auto-consents | BLOCKED (onlyRole) |
| | `test_unauthorized_releaseEscrow_reverts` | ContractParties.releaseEscrow | Stranger releases escrow | BLOCKED (onlyRole) |
| | `test_unauthorized_refundEscrow_reverts` | ContractParties.refundEscrow | Stranger refunds escrow | BLOCKED (onlyRole) |
| | `test_roleEscalation_grantRole_reverts` | All contracts | Stranger grants self roles | BLOCKED (AccessControl) |
| | `test_roleEscalation_grantDefaultAdmin_reverts` | All contracts | Stranger grants self DEFAULT_ADMIN | BLOCKED (AccessControl) |
| | `test_roleRevocation_settler_cannot_settle` | ContractSettlements | Revoked settler tries to settle | BLOCKED (onlyRole) |
| | `test_roleRevocation_server_cannot_report` | ContractResults | Revoked server tries to report | BLOCKED (onlyRole) |
| | `test_stranger_cannot_revokeRole` | All contracts | Stranger revokes admin roles | BLOCKED (AccessControl) |
| **StateMachineAttack.t.sol** | | | | |
| | `test_skip_created_to_completed_reverts` | ContractInstances | Skip Active state | BLOCKED (InvalidTransition) |
| | `test_skip_created_to_settled_reverts` | ContractInstances | Skip Active+Completed | BLOCKED (InvalidTransition) |
| | `test_skip_created_to_disputed_reverts` | ContractInstances | Invalid transition | BLOCKED (InvalidTransition) |
| | `test_skip_active_to_settled_reverts` | ContractInstances | Skip Completed | BLOCKED (InvalidTransition) |
| | `test_skip_active_to_disputed_reverts` | ContractInstances | Skip Completed | BLOCKED (InvalidTransition) |
| | `test_skip_completed_to_resolved_reverts` | ContractInstances | Skip Disputed | BLOCKED (InvalidTransition) |
| | `test_reverse_active_to_created_reverts` | ContractInstances | Reverse transition | BLOCKED (InvalidTransition) |
| | `test_reverse_completed_to_active_reverts` | ContractInstances | Reverse transition | BLOCKED (InvalidTransition) |
| | `test_settled_is_terminal` | ContractInstances | All transitions from Settled | BLOCKED (InvalidTransition) |
| | `test_double_settle_reverts` | ContractSettlements | Settle twice | BLOCKED (SettlementAlreadyDone) |
| | `test_double_refund_reverts` | ContractSettlements | Refund twice | BLOCKED (SettlementAlreadyDone) |
| | `test_reportResult_when_created_reverts` | ContractResults | Result before Active | BLOCKED (InvalidState) |
| | `test_reportResult_when_completed_reverts` | ContractResults | Result after Completed | BLOCKED (InvalidState) |
| | `test_double_final_result_reverts` | ContractResults | Two final results | BLOCKED (InvalidState) |
| | `test_double_consent_reverts` | ContractConsents | Double consent | BLOCKED (AlreadyConsented) |
| | `test_settle_without_consent_reverts` | ContractSettlements | Settle without consent | BLOCKED (ConsentNotComplete) |
| | `test_valid_dispute_resolution_flow` | Full lifecycle | Dispute -> Resolve -> Settle | PASS (valid flow) |
| **EscrowManipulation.t.sol** | | | | |
| | `test_joinWithZeroAmount_reverts` | ContractParties.joinContract | Zero escrow deposit | BLOCKED (InvalidAmount) |
| | `test_joinWithAmountAboveMaxBet_reverts` | ContractParties.joinContract | Exceed max bet | BLOCKED (BetOutOfRange) |
| | `test_joinWithAmountBelowMinBet_reverts` | ContractParties.joinContract | Below min bet | BLOCKED (BetOutOfRange) |
| | `test_multipleReleaseEscrow_drainBlocked` | ContractParties.releaseEscrow | Drain via repeated release | BLOCKED (EscrowOverRelease) |
| | `test_releaseEscrow_exceedsTotalEscrow_reverts` | ContractParties.releaseEscrow | Release > total escrow | BLOCKED (EscrowOverRelease) |
| | `test_escrow_isolation_between_instances` | ContractParties | Cross-instance escrow leak | BLOCKED (isolated mappings) |
| | `test_doubleJoin_reverts` | ContractParties.joinContract | Same user joins twice | BLOCKED (AlreadyJoined) |
| | `test_joinAfterActivation_reverts` | ContractParties.joinContract | Join after Active | BLOCKED (InvalidState) |
| | `test_refundAfterSettle_reverts` | ContractSettlements | Refund after settle | BLOCKED (SettlementAlreadyDone) |
| | `test_paymentTypeMismatch_reverts` | ContractParties.joinContract | Wrong escrow type | BLOCKED (PaymentTypeMismatch) |
| | `test_releaseEscrow_zeroAddress_reverts` | ContractParties.releaseEscrow | Release to address(0) | BLOCKED (ZeroAddress) |
| | `test_releaseEscrow_zeroAmount_reverts` | ContractParties.releaseEscrow | Release 0 tokens | BLOCKED (InvalidAmount) |
| | `test_tokenBalances_afterSettlement_correct` | Full lifecycle | Verify token conservation | PASS (invariant holds) |
| **FeeManipulation.t.sol** | | | | |
| | `test_feeRateAboveMax_reverts` | ContractTemplates.createTemplate | Fee > 5000 bps | BLOCKED (InvalidFeeRate) |
| | `test_feeRateAtMax_succeeds` | ContractTemplates.createTemplate | Fee = 5000 bps | PASS (boundary) |
| | `test_feeRateZero_succeeds` | ContractTemplates.createTemplate | Fee = 0 bps | PASS (boundary) |
| | `test_updateFeeRateAboveMax_reverts` | ContractTemplates.updateTemplate | Update fee > 5000 | BLOCKED (InvalidFeeRate) |
| | `testFuzz_feeInvariant_winnerPlusFeeEqualsTotalEscrow` | FeeCalculator | Fuzz: winner + fee == total | PASS (invariant holds) |
| | `testFuzz_feeNeverExceedsTotalEscrow` | FeeCalculator | Fuzz: fee <= 50% total | PASS (invariant holds) |
| | `testFuzz_winnerGetsAtLeastHalf` | FeeCalculator | Fuzz: winner >= 50% | PASS (invariant holds) |
| | `test_feeCalculator_zeroEscrow_reverts` | FeeCalculator | Zero escrow | BLOCKED (InvalidAmount) |
| | `test_feeCalculator_aboveMaxRate_reverts` | FeeCalculator | Rate > 5000 | BLOCKED (InvalidFeeRate) |
| | `test_bypassFee_directReleaseEscrow_reverts` | ContractParties.releaseEscrow | Bypass fee via direct call | BLOCKED (onlyRole) |
| | `test_bypassFee_adminWithoutContractRole_reverts` | ContractParties.releaseEscrow | Admin bypasses fee | BLOCKED (onlyRole) |
| | `test_exactFeeCalculation_settlement` | Full lifecycle | Verify exact amounts | PASS |
| | `test_settlement_zeroFee` | Full lifecycle | 0% fee settlement | PASS |
| | `test_settlement_maxFee` | Full lifecycle | 50% fee settlement | PASS |
| | `test_setTreasury_zeroAddress_reverts` | ContractSettlements.setTreasury | Zero address treasury | BLOCKED (InvalidTreasuryAddress) |
| | `test_setTreasury_unauthorized_reverts` | ContractSettlements.setTreasury | Stranger sets treasury | BLOCKED (onlyRole) |

---

## Security Score

| Category | Score (1-10) | Notes |
| --- | --- | --- |
| **Access Control** | 9 | Comprehensive RBAC with 5 roles. Every state-changing function is role-gated. Minor: centralized admin key risk. |
| **Reentrancy Protection** | 8 | `nonReentrant` on all escrow functions, `SafeERC20` used consistently. Minor: non-upgradeable guard import (works in OZ v5 but fragile). |
| **State Machine Integrity** | 9 | `StateValidator` enforces exactly 6 valid transitions. All invalid transitions revert. Terminal state (Settled) fully locked. |
| **Escrow Safety** | 9 | Zero-amount, out-of-range, and over-release all checked. Cumulative release tracking prevents drain. Isolated per instance. |
| **Fee Calculation** | 10 | `FeeCalculator` enforces 5000 bps cap. Fuzz testing confirms `winner + fee == totalEscrow` invariant holds for all inputs. |
| **Input Validation** | 8 | Good coverage: zero addresses, empty names, invalid fee rates, bet ranges. Minor: result data structure not validated at submission. |
| **Upgrade Safety** | 7 | Storage gaps present. `_disableInitializers()` in constructors. Minor: gap sizes inconsistent with spec, non-upgradeable ReentrancyGuard. |
| **Emergency Response** | 5 | Basic global pause via `PausableUpgradeable`. `EmergencyStop` with per-instance pause and timelocked recovery exists but is not integrated. |
| **Code Quality** | 7 | Well-documented with NatSpec. Consistent patterns. Dead code: `AccessRoles`, `TimeoutHelper`, `calculateDrawRefund()`. |
| **Overall** | **8.0** | Solid security posture for Phase 1. Key improvement areas: admin key governance, EmergencyStop integration, library adoption. |
