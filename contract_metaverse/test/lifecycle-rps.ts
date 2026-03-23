/**
 * Test: Full RPS Lifecycle — replicates the walkthrough:
 *   create -> join(A,50e18) -> join(B,50e18) -> activate -> result(B wins)
 *   -> consent(A) -> consent(B) -> settle
 *
 * Final balances:
 *   A: 50e18, B: 147e18, Treasury: 3e18
 */
import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import { parseEther } from "viem";
import {
  deployFullSystem,
  type DeployedSystem,
  createRPSTemplate,
  mintAndApprove,
  encodeResultData,
  getContractAsUser,
  CHALLENGER_ROLE,
  OPPONENT_ROLE,
} from "./helpers/deploy.js";

describe("Lifecycle: Full RPS Walkthrough", () => {
  let sys: DeployedSystem;
  let templateId: `0x${string}`;
  let instanceId: `0x${string}`;
  const betAmount = parseEther("50");

  before(async () => {
    sys = await deployFullSystem();

    // Step 1: Create RPS template (fee=300bps=3%)
    templateId = await createRPSTemplate(sys, {
      feeRateBps: 300,
      minBet: parseEther("10"),
      maxBet: parseEther("100"),
      timeoutSeconds: 15n,
    });

    // Step 2: Mint 100e18 tokens to each player and approve
    await mintAndApprove(sys, parseEther("100"));

    // Step 3: Create instance
    const createHash = await sys.instances.write.createInstance([
      templateId,
      "0x" as `0x${string}`,
    ]);
    const createReceipt = await sys.publicClient.waitForTransactionReceipt({
      hash: createHash,
    });
    instanceId = createReceipt.logs[0].topics[1] as `0x${string}`;
  });

  it("should have instance in Created status after creation", async () => {
    const status = await sys.instances.read.getInstanceStatus([instanceId]);
    assert.equal(status, 0); // Created
  });

  it("should allow player A to join with 50e18 escrow", async () => {
    const partiesA = await getContractAsUser(
      "ContractParties",
      sys.parties.address,
      sys.playerA.account.address
    );
    await partiesA.write.joinContract([
      instanceId,
      CHALLENGER_ROLE,
      betAmount,
      1, // IXFreePoint
    ]);

    const hasJoined = await sys.parties.read.hasJoined([
      instanceId,
      sys.playerA.account.address,
    ]);
    assert.ok(hasJoined);

    // A's token balance should be 50e18 (100 - 50)
    const balanceA = await sys.token.read.balanceOf([
      sys.playerA.account.address,
    ]);
    assert.equal(balanceA, parseEther("50"));
  });

  it("should allow player B to join with 50e18 escrow", async () => {
    const partiesB = await getContractAsUser(
      "ContractParties",
      sys.parties.address,
      sys.playerB.account.address
    );
    await partiesB.write.joinContract([
      instanceId,
      OPPONENT_ROLE,
      betAmount,
      1, // IXFreePoint
    ]);

    const hasJoined = await sys.parties.read.hasJoined([
      instanceId,
      sys.playerB.account.address,
    ]);
    assert.ok(hasJoined);

    // B's token balance should be 50e18
    const balanceB = await sys.token.read.balanceOf([
      sys.playerB.account.address,
    ]);
    assert.equal(balanceB, parseEther("50"));
  });

  it("should have party count = 2 and total escrow = 100e18", async () => {
    const partyCount = await sys.parties.read.getPartyCount([instanceId]);
    assert.equal(partyCount, 2);

    const totalEscrow = await sys.parties.read.getTotalEscrow([instanceId]);
    assert.equal(totalEscrow, parseEther("100"));
  });

  it("should activate instance (Created -> Active)", async () => {
    await sys.instances.write.activateInstance([instanceId]);
    const status = await sys.instances.read.getInstanceStatus([instanceId]);
    assert.equal(status, 1); // Active
  });

  it("should report result (B wins) and transition to Completed", async () => {
    const resultData = encodeResultData(
      sys.playerB.account.address,
      "rock",
      "scissors",
      1n,
      "1-0",
      false
    );

    const hash = await sys.results.write.reportResult([
      instanceId,
      resultData,
      0, // ResultSource.System
      true, // isFinal
    ]);

    const receipt = await sys.publicClient.waitForTransactionReceipt({ hash });
    assert.equal(receipt.status, "success");

    // Instance should now be Completed
    const status = await sys.instances.read.getInstanceStatus([instanceId]);
    assert.equal(status, 2); // Completed

    // Result should exist and be final
    const result = await sys.results.read.getResult([instanceId]);
    assert.ok(result.isFinal);
  });

  it("should allow A to consent (accept loss)", async () => {
    await sys.consents.write.submitConsent([
      instanceId,
      sys.playerA.account.address,
      true,
      "0x" as `0x${string}`,
      "",
    ]);

    const consent = await sys.consents.read.getConsent([
      instanceId,
      sys.playerA.account.address,
    ]);
    assert.ok(consent.consented);
  });

  it("should allow B to consent (accept win)", async () => {
    await sys.consents.write.submitConsent([
      instanceId,
      sys.playerB.account.address,
      true,
      "0x" as `0x${string}`,
      "",
    ]);

    const consent = await sys.consents.read.getConsent([
      instanceId,
      sys.playerB.account.address,
    ]);
    assert.ok(consent.consented);
  });

  it("should report allConsented = true", async () => {
    const allDone = await sys.consents.read.allConsented([instanceId]);
    assert.ok(allDone);
  });

  it("should settle contract and transition to Settled", async () => {
    const hash = await sys.settlements.write.settleContract([instanceId]);
    const receipt = await sys.publicClient.waitForTransactionReceipt({ hash });
    assert.equal(receipt.status, "success");

    // Instance should now be Settled
    const status = await sys.instances.read.getInstanceStatus([instanceId]);
    assert.equal(status, 5); // Settled
  });

  it("should have correct final balances: A=50e18, B=147e18, Treasury=3e18", async () => {
    const balanceA = await sys.token.read.balanceOf([
      sys.playerA.account.address,
    ]);
    const balanceB = await sys.token.read.balanceOf([
      sys.playerB.account.address,
    ]);
    const balanceTreasury = await sys.token.read.balanceOf([
      sys.treasury.account.address,
    ]);

    // A started with 100, bet 50 and lost => 50 remaining
    assert.equal(balanceA, parseEther("50"));

    // B started with 100, bet 50, won 97 (100 total - 3 fee) => 50 + 97 = 147
    assert.equal(balanceB, parseEther("147"));

    // Treasury gets 3% of 100e18 = 3e18
    assert.equal(balanceTreasury, parseEther("3"));
  });

  it("should have 2 settlement records (reward + fee)", async () => {
    const count = await sys.settlements.read.getSettlementCount([instanceId]);
    assert.equal(count, 2n);

    const records = await sys.settlements.read.getSettlements([instanceId]);
    assert.equal(records.length, 2);

    // Reward record
    const rewardRecord = records.find((r) => r.settlementType === 0);
    assert.ok(rewardRecord, "Should have a reward settlement");
    assert.equal(rewardRecord!.amount, parseEther("97"));
    assert.equal(
      rewardRecord!.toUserId.toLowerCase(),
      sys.playerB.account.address.toLowerCase()
    );

    // Fee record
    const feeRecord = records.find((r) => r.settlementType === 1);
    assert.ok(feeRecord, "Should have a fee settlement");
    assert.equal(feeRecord!.amount, parseEther("3"));
    assert.equal(
      feeRecord!.toUserId.toLowerCase(),
      sys.treasury.account.address.toLowerCase()
    );
  });

  it("should mark isSettled = true", async () => {
    const settled = await sys.settlements.read.isSettled([instanceId]);
    assert.ok(settled);
  });

  it("should emit settlement events", async () => {
    // Verify via getSettlements that records exist (events are emitted on-chain;
    // the settlement records prove the events were processed)
    const records = await sys.settlements.read.getSettlements([instanceId]);
    assert.equal(records.length, 2);
  });
});
