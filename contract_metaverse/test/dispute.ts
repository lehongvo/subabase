/**
 * Test: Dispute Flow — A disputes -> admin resolves -> settle.
 * Also tests timeout auto-consent.
 */
import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import { parseEther } from "viem";
import { network } from "hardhat";
import {
  deployFullSystem,
  type DeployedSystem,
  createRPSTemplate,
  mintAndApprove,
  encodeResultData,
  joinContractAs,
  CHALLENGER_ROLE,
  OPPONENT_ROLE,
} from "./helpers/deploy.js";

/**
 * Helper: set up a completed instance (A and B joined, activated, result reported, B wins)
 */
async function setupCompletedInstance(sys: DeployedSystem, timeoutSeconds = 15n) {
  const betAmount = parseEther("50");
  const templateId = await createRPSTemplate(sys, {
    name: `RPS Dispute ${Date.now()}`,
    timeoutSeconds,
    minBet: parseEther("10"),
    maxBet: parseEther("100"),
  });

  await mintAndApprove(sys, parseEther("100"));

  const createHash = await sys.instances.write.createInstance([
    templateId,
    "0x" as `0x${string}`,
  ]);
  const createReceipt = await sys.publicClient.waitForTransactionReceipt({
    hash: createHash,
  });
  const instanceId = createReceipt.logs[0].topics[1] as `0x${string}`;

  // A joins
  await joinContractAs(sys, sys.playerA, instanceId, CHALLENGER_ROLE, betAmount, 1);

  // B joins
  await joinContractAs(sys, sys.playerB, instanceId, OPPONENT_ROLE, betAmount, 1);

  // Activate
  await sys.instances.write.activateInstance([instanceId]);

  // Report result (B wins)
  const resultData = encodeResultData(
    sys.playerB.account.address,
    "rock",
    "scissors",
    1n,
    "1-0",
    false
  );
  await sys.results.write.reportResult([
    instanceId,
    resultData,
    0,
    true,
  ]);

  return { instanceId, templateId, betAmount };
}

describe("Dispute Flow", () => {
  // ========================================================================
  // Full dispute: A disputes -> admin resolves -> settle
  // ========================================================================
  describe("A disputes -> admin resolves -> settle", () => {
    let sys: DeployedSystem;
    let instanceId: `0x${string}`;

    before(async () => {
      sys = await deployFullSystem();
      const setup = await setupCompletedInstance(sys);
      instanceId = setup.instanceId;
    });

    it("should be in Completed status before dispute", async () => {
      const status = await sys.instances.read.getInstanceStatus([instanceId]);
      assert.equal(status, 2); // Completed
    });

    it("should allow A to dispute (consented=false)", async () => {
      await sys.consents.write.submitConsent([
        instanceId,
        sys.playerA.account.address,
        false, // dispute
        "0x" as `0x${string}`,
        "Server lagged, my move was not registered correctly",
      ]);

      const consent = await sys.consents.read.getConsent([
        instanceId,
        sys.playerA.account.address,
      ]);
      assert.equal(consent.consented, false);
    });

    it("should transition to Disputed after A disputes", async () => {
      const status = await sys.instances.read.getInstanceStatus([instanceId]);
      assert.equal(status, 3); // Disputed
    });

    it("should report hasDispute = true", async () => {
      const disputed = await sys.consents.read.hasDispute([instanceId]);
      assert.ok(disputed);
    });

    it("should allow admin to resolve the dispute", async () => {
      await sys.instances.write.resolveInstance([instanceId]);
      const status = await sys.instances.read.getInstanceStatus([instanceId]);
      assert.equal(status, 4); // Resolved
    });

    it("should allow B to consent after resolution", async () => {
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

    it("should settle after dispute resolution (Resolved -> Settled)", async () => {
      await sys.settlements.write.settleContract([instanceId]);
      const status = await sys.instances.read.getInstanceStatus([instanceId]);
      assert.equal(status, 5); // Settled
    });

    it("should have correct balances after disputed settlement", async () => {
      const balanceA = await sys.token.read.balanceOf([
        sys.playerA.account.address,
      ]);
      const balanceB = await sys.token.read.balanceOf([
        sys.playerB.account.address,
      ]);
      const balanceTreasury = await sys.token.read.balanceOf([
        sys.treasury.account.address,
      ]);

      // Same outcome as normal: A=50, B=147, Treasury=3
      assert.equal(balanceA, parseEther("50"));
      assert.equal(balanceB, parseEther("147"));
      assert.equal(balanceTreasury, parseEther("3"));
    });
  });

  // ========================================================================
  // Timeout auto-consent
  // ========================================================================
  describe("Timeout auto-consent", () => {
    let sys: DeployedSystem;
    let instanceId: `0x${string}`;

    before(async () => {
      sys = await deployFullSystem();
      // Use the minimum enforceable timeout of 10 seconds
      const setup = await setupCompletedInstance(sys, 10n);
      instanceId = setup.instanceId;
    });

    it("should allow A to consent normally and set deadline", async () => {
      await sys.consents.write.submitConsent([
        instanceId,
        sys.playerA.account.address,
        true,
        "0x" as `0x${string}`,
        "",
      ]);

      const count = await sys.consents.read.getConsentCount([instanceId]);
      assert.equal(count, 1);

      // Verify deadline is set
      const deadline = await sys.consents.read.getConsentDeadline([instanceId]);
      assert.ok(deadline > 0, `Consent deadline should be set, got ${deadline}`);
    });

    it("should reject autoConsent before timeout expires", async () => {
      await assert.rejects(
        async () => {
          await sys.consents.write.autoConsent([
            instanceId,
            sys.playerB.account.address,
          ]);
        },
        (err: any) => true,
        "autoConsent should fail before timeout"
      );
    });

    it("should allow autoConsent after timeout expires and then settle", async () => {
      // Read the consent deadline
      const deadline = await sys.consents.read.getConsentDeadline([instanceId]);
      assert.ok(deadline > 0, "Deadline should be set");

      // Advance block timestamp well past the consent deadline
      // IMPORTANT: use sys.testClient (same network connection as the deployed contracts)
      const targetTimestamp = BigInt(deadline) + 600n;
      await sys.testClient.setNextBlockTimestamp({ timestamp: targetTimestamp });
      await sys.testClient.mine({ blocks: 1 });

      // Verify block timestamp using sys.publicClient (same network)
      const block = await sys.publicClient.getBlock();
      assert.ok(
        block.timestamp > BigInt(deadline),
        `Block time ${block.timestamp} should exceed deadline ${deadline}`
      );

      // autoConsent should now succeed since block time is past deadline
      await sys.consents.write.autoConsent([
        instanceId,
        sys.playerB.account.address,
      ]);

      const allDone = await sys.consents.read.allConsented([instanceId]);
      assert.ok(allDone);

      // Settle
      await sys.settlements.write.settleContract([instanceId]);
      const status = await sys.instances.read.getInstanceStatus([instanceId]);
      assert.equal(status, 5); // Settled
    });
  });
});
