/**
 * Sanity test: check basic contract function calls
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { network } from "hardhat";
import { parseEther } from "viem";
import {
  deployFullSystem,
  createRPSTemplate,
  CHALLENGER_ROLE,
} from "./helpers/deploy.js";

describe("Sanity", () => {
  it("should read hasJoined (view call)", async () => {
    const sys = await deployFullSystem();

    const templateId = await createRPSTemplate(sys);

    const createHash = await sys.instances.write.createInstance([
      templateId,
      "0x" as `0x${string}`,
    ]);
    const { viem } = await network.connect();
    const publicClient = await viem.getPublicClient();
    const receipt = await publicClient.waitForTransactionReceipt({ hash: createHash });
    const instanceId = receipt.logs[0].topics[1] as `0x${string}`;

    // View call should work
    const hasJoined = await sys.parties.read.hasJoined([instanceId, sys.admin.account.address]);
    console.log("hasJoined:", hasJoined);
    assert.equal(hasJoined, false);

    // Check status
    const status = await sys.instances.read.getInstanceStatus([instanceId]);
    console.log("status:", status);
    assert.equal(status, 0); // Created

    // Check template
    const tmpl = await sys.templates.read.getTemplate([templateId]);
    console.log("template isActive:", tmpl.isActive);
    assert.ok(tmpl.isActive);

    // Check token things
    await sys.token.write.mint([sys.admin.account.address, parseEther("100")]);
    await sys.token.write.approve([sys.parties.address, parseEther("100")]);

    const balance = await sys.token.read.balanceOf([sys.admin.account.address]);
    console.log("admin balance:", balance);
    assert.equal(balance, parseEther("100"));

    const allowance = await sys.token.read.allowance([sys.admin.account.address, sys.parties.address]);
    console.log("admin allowance:", allowance);
    assert.equal(allowance, parseEther("100"));

    // Now try a static call to estimate gas for joinContract
    console.log("About to simulate joinContract...");
    try {
      const simResult = await publicClient.simulateContract({
        address: sys.parties.address,
        abi: sys.parties.abi,
        functionName: "joinContract",
        args: [instanceId, CHALLENGER_ROLE, parseEther("50"), 1],
        account: sys.admin.account,
      });
      console.log("simulateContract succeeded, request:", simResult.request);
    } catch (err: any) {
      console.log("simulateContract error:", err.message?.substring(0, 500));
    }
  });
});
