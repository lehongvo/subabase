/**
 * Sanity test: verify joinContract works with explicit gas
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { network } from "hardhat";
import { parseEther, keccak256, toHex } from "viem";
import {
  deployFullSystem,
  createRPSTemplate,
  mintAndApprove,
  CHALLENGER_ROLE,
  OPPONENT_ROLE,
  getContractAsUser,
} from "./helpers/deploy.js";

describe("Sanity: joinContract", () => {
  it("should allow playerA to join via writeContract with explicit gas", async () => {
    const sys = await deployFullSystem();
    const { viem } = await network.connect();
    const publicClient = await viem.getPublicClient();

    const templateId = await createRPSTemplate(sys);
    await mintAndApprove(sys, parseEther("100"));

    const createHash = await sys.instances.write.createInstance([
      templateId,
      "0x" as `0x${string}`,
    ]);
    const receipt = await publicClient.waitForTransactionReceipt({ hash: createHash });
    const instanceId = receipt.logs[0].topics[1] as `0x${string}`;

    // Check approval
    const allowance = await sys.token.read.allowance([
      sys.playerA.account.address,
      sys.parties.address,
    ]);
    console.log("allowance:", allowance);

    // Check balance
    const bal = await sys.token.read.balanceOf([sys.playerA.account.address]);
    console.log("balance:", bal);

    // Try joinContract with explicit gas
    const joinHash = await sys.playerA.writeContract({
      address: sys.parties.address,
      abi: sys.parties.abi,
      functionName: "joinContract",
      args: [instanceId, CHALLENGER_ROLE, parseEther("50"), 1],
      gas: 500_000n,
    });
    console.log("joinHash:", joinHash);

    const joinReceipt = await publicClient.waitForTransactionReceipt({
      hash: joinHash,
      timeout: 10_000,
    });
    console.log("joinReceipt status:", joinReceipt.status);

    const hasJoined = await sys.parties.read.hasJoined([instanceId, sys.playerA.account.address]);
    assert.ok(hasJoined, "playerA should have joined");
  });
});
