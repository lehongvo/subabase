/**
 * Test: Edge Cases — revert conditions for various boundary scenarios.
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
  joinContractAs,
  runFullRPSLifecycle,
  CHALLENGER_ROLE,
  OPPONENT_ROLE,
} from "./helpers/deploy.js";

describe("Edge Cases", () => {
  let sys: DeployedSystem;

  before(async () => {
    sys = await deployFullSystem();
  });

  // ========================================================================
  // Bet below min -> revert
  // ========================================================================
  it("should revert when bet is below minimum", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Min Bet Test",
      minBet: parseEther("10"),
      maxBet: parseEther("100"),
    });

    await mintAndApprove(sys, parseEther("1000"));

    const createHash = await sys.instances.write.createInstance([
      templateId,
      "0x" as `0x${string}`,
    ]);
    const receipt = await sys.publicClient.waitForTransactionReceipt({
      hash: createHash,
    });
    const instanceId = receipt.logs[0].topics[1] as `0x${string}`;

    // Try to join with 5e18 (below min of 10e18)
    await assert.rejects(
      async () => {
        await joinContractAs(
          sys,
          sys.playerA,
          instanceId,
          CHALLENGER_ROLE,
          parseEther("5"), // below min_bet of 10
          1
        );
      },
      (err: any) => true,
      "Bet below minimum should revert with BetOutOfRange"
    );
  });

  // ========================================================================
  // Bet above max -> revert
  // ========================================================================
  it("should revert when bet is above maximum", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Max Bet Test",
      minBet: parseEther("10"),
      maxBet: parseEther("100"),
    });

    // Mint extra tokens to playerA
    await sys.token.write.mint([sys.playerA.account.address, parseEther("200")]);
    await sys.playerA.writeContract({
      address: sys.token.address,
      abi: [{
        name: "approve",
        type: "function" as const,
        inputs: [
          { name: "spender", type: "address" as const },
          { name: "amount", type: "uint256" as const },
        ],
        outputs: [{ type: "bool" as const }],
        stateMutability: "nonpayable" as const,
      }],
      functionName: "approve",
      args: [sys.parties.address, parseEther("200")],
    });

    const createHash = await sys.instances.write.createInstance([
      templateId,
      "0x" as `0x${string}`,
    ]);
    const receipt = await sys.publicClient.waitForTransactionReceipt({
      hash: createHash,
    });
    const instanceId = receipt.logs[0].topics[1] as `0x${string}`;

    // Try to join with 150e18 (above max of 100e18)
    await assert.rejects(
      async () => {
        await joinContractAs(
          sys,
          sys.playerA,
          instanceId,
          CHALLENGER_ROLE,
          parseEther("150"), // above max_bet of 100
          1
        );
      },
      (err: any) => true,
      "Bet above maximum should revert with BetOutOfRange"
    );
  });

  // ========================================================================
  // Join inactive template -> revert
  // ========================================================================
  it("should revert when joining contract from deactivated template", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Inactive Template Test",
    });

    // Create instance while template is active
    const createHash = await sys.instances.write.createInstance([
      templateId,
      "0x" as `0x${string}`,
    ]);
    const receipt = await sys.publicClient.waitForTransactionReceipt({
      hash: createHash,
    });
    const instanceId = receipt.logs[0].topics[1] as `0x${string}`;

    // Deactivate the template
    await sys.templates.write.deactivateTemplate([templateId]);

    // Mint and approve for playerA
    await sys.token.write.mint([sys.playerA.account.address, parseEther("100")]);
    await sys.playerA.writeContract({
      address: sys.token.address,
      abi: [{
        name: "approve",
        type: "function" as const,
        inputs: [
          { name: "spender", type: "address" as const },
          { name: "amount", type: "uint256" as const },
        ],
        outputs: [{ type: "bool" as const }],
        stateMutability: "nonpayable" as const,
      }],
      functionName: "approve",
      args: [sys.parties.address, parseEther("100")],
    });

    // Attempt to join with inactive template
    await assert.rejects(
      async () => {
        await joinContractAs(
          sys,
          sys.playerA,
          instanceId,
          CHALLENGER_ROLE,
          parseEther("50"),
          1
        );
      },
      (err: any) => true,
      "Joining contract with inactive template should revert"
    );
  });

  // ========================================================================
  // Double settle -> revert
  // ========================================================================
  it("should revert on double settlement", async () => {
    // We need a fresh system for this test to avoid token state pollution
    const freshSys = await deployFullSystem();
    const { instanceId } = await runFullRPSLifecycle(freshSys);

    // Verify it's settled
    const settled = await freshSys.settlements.read.isSettled([instanceId]);
    assert.ok(settled);

    // Try to settle again
    await assert.rejects(
      async () => {
        await freshSys.settlements.write.settleContract([instanceId]);
      },
      (err: any) => true,
      "Double settlement should revert with SettlementAlreadyDone"
    );
  });

  // ========================================================================
  // Join after activation -> revert
  // ========================================================================
  it("should revert when trying to join after instance is activated", async () => {
    const freshSys = await deployFullSystem();

    const templateId = await createRPSTemplate(freshSys, {
      name: "RPS Join After Activate",
    });

    await mintAndApprove(freshSys, parseEther("100"));

    const createHash = await freshSys.instances.write.createInstance([
      templateId,
      "0x" as `0x${string}`,
    ]);
    const receipt = await freshSys.publicClient.waitForTransactionReceipt({
      hash: createHash,
    });
    const instanceId = receipt.logs[0].topics[1] as `0x${string}`;

    // A joins
    await joinContractAs(freshSys, freshSys.playerA, instanceId, CHALLENGER_ROLE, parseEther("50"), 1);

    // B joins
    await joinContractAs(freshSys, freshSys.playerB, instanceId, OPPONENT_ROLE, parseEther("50"), 1);

    // Activate
    await freshSys.instances.write.activateInstance([instanceId]);

    // Verify status is Active
    const status = await freshSys.instances.read.getInstanceStatus([instanceId]);
    assert.equal(status, 1); // Active

    // outsider tries to join after activation
    await freshSys.token.write.mint([freshSys.outsider.account.address, parseEther("100")]);
    await freshSys.outsider.writeContract({
      address: freshSys.token.address,
      abi: [{
        name: "approve",
        type: "function" as const,
        inputs: [
          { name: "spender", type: "address" as const },
          { name: "amount", type: "uint256" as const },
        ],
        outputs: [{ type: "bool" as const }],
        stateMutability: "nonpayable" as const,
      }],
      functionName: "approve",
      args: [freshSys.parties.address, parseEther("100")],
    });

    await assert.rejects(
      async () => {
        await joinContractAs(
          freshSys,
          freshSys.outsider,
          instanceId,
          CHALLENGER_ROLE,
          parseEther("50"),
          1
        );
      },
      (err: any) => true,
      "Joining after activation should revert (status != Created)"
    );
  });

  // ========================================================================
  // Create instance from inactive template -> revert
  // ========================================================================
  it("should revert when creating instance from deactivated template", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Create Instance Inactive",
    });

    await sys.templates.write.deactivateTemplate([templateId]);

    await assert.rejects(
      async () => {
        await sys.instances.write.createInstance([
          templateId,
          "0x" as `0x${string}`,
        ]);
      },
      (err: any) => true,
      "Creating instance from inactive template should revert"
    );
  });

  // ========================================================================
  // Activate with fewer than 2 parties -> revert
  // ========================================================================
  it("should revert when activating with fewer than 2 parties", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Activate No Parties",
    });

    const createHash = await sys.instances.write.createInstance([
      templateId,
      "0x" as `0x${string}`,
    ]);
    const receipt = await sys.publicClient.waitForTransactionReceipt({
      hash: createHash,
    });
    const instanceId = receipt.logs[0].topics[1] as `0x${string}`;

    // Only A joins
    await sys.token.write.mint([sys.playerA.account.address, parseEther("100")]);
    await sys.playerA.writeContract({
      address: sys.token.address,
      abi: [{
        name: "approve",
        type: "function" as const,
        inputs: [
          { name: "spender", type: "address" as const },
          { name: "amount", type: "uint256" as const },
        ],
        outputs: [{ type: "bool" as const }],
        stateMutability: "nonpayable" as const,
      }],
      functionName: "approve",
      args: [sys.parties.address, parseEther("100")],
    });

    await joinContractAs(sys, sys.playerA, instanceId, CHALLENGER_ROLE, parseEther("50"), 1);

    // Try to activate with only 1 party
    await assert.rejects(
      async () => {
        await sys.instances.write.activateInstance([instanceId]);
      },
      (err: any) => true,
      "Activating with < 2 parties should revert"
    );
  });

  // ========================================================================
  // Zero escrow amount -> revert
  // ========================================================================
  it("should revert when escrow amount is zero", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Zero Escrow",
    });

    const createHash = await sys.instances.write.createInstance([
      templateId,
      "0x" as `0x${string}`,
    ]);
    const receipt = await sys.publicClient.waitForTransactionReceipt({
      hash: createHash,
    });
    const instanceId = receipt.logs[0].topics[1] as `0x${string}`;

    await assert.rejects(
      async () => {
        await joinContractAs(
          sys,
          sys.playerA,
          instanceId,
          CHALLENGER_ROLE,
          0n, // zero escrow
          1
        );
      },
      (err: any) => true,
      "Zero escrow should revert with InvalidAmount"
    );
  });

  // ========================================================================
  // Double join by same user -> revert
  // ========================================================================
  it("should revert when same user tries to join twice", async () => {
    const freshSys = await deployFullSystem();
    const templateId = await createRPSTemplate(freshSys, {
      name: "RPS Double Join",
    });

    await mintAndApprove(freshSys, parseEther("200"));

    const createHash = await freshSys.instances.write.createInstance([
      templateId,
      "0x" as `0x${string}`,
    ]);
    const receipt = await freshSys.publicClient.waitForTransactionReceipt({
      hash: createHash,
    });
    const instanceId = receipt.logs[0].topics[1] as `0x${string}`;

    // First join succeeds
    await joinContractAs(freshSys, freshSys.playerA, instanceId, CHALLENGER_ROLE, parseEther("50"), 1);

    // Second join should fail
    await assert.rejects(
      async () => {
        await joinContractAs(freshSys, freshSys.playerA, instanceId, OPPONENT_ROLE, parseEther("50"), 1);
      },
      (err: any) => true,
      "Same user joining twice should revert with AlreadyJoined"
    );
  });
});
