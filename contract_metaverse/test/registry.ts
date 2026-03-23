/**
 * Test: Registry (ContractTemplates) — template CRUD, activate/deactivate,
 * admin-only enforcement.
 */
import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import { parseEther } from "viem";
import {
  deployFullSystem,
  type DeployedSystem,
  createRPSTemplate,
  encodeConditions,
  encodeRewardRules,
  getContractAsUser,
} from "./helpers/deploy.js";

describe("Registry (ContractTemplates)", () => {
  let sys: DeployedSystem;

  before(async () => {
    sys = await deployFullSystem();
  });

  // ========================================================================
  // Create RPS template
  // ========================================================================

  it("should create an RPS template with correct parameters", async () => {
    const templateId = await createRPSTemplate(sys);

    const tmpl = await sys.templates.read.getTemplate([templateId]);

    assert.equal(tmpl.contractType, 0); // RPS
    assert.equal(tmpl.feeRateBps, 300);
    assert.equal(tmpl.isActive, true);
    assert.equal(tmpl.paymentType, 1); // IXFreePoint
    assert.equal(tmpl.chainRecordPolicy, 0); // Required
    assert.equal(tmpl.name, "RPS Casual Lobby 1");
  });

  it("should increment template count after creation", async () => {
    const countBefore = await sys.templates.read.getTemplateCount();
    await createRPSTemplate(sys, { name: "RPS Count Test" });
    const countAfter = await sys.templates.read.getTemplateCount();
    assert.equal(countAfter, countBefore + 1n);
  });

  it("should return template in getActiveTemplates", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Active Query Test",
    });
    const activeTemplates = await sys.templates.read.getActiveTemplates();
    const found = activeTemplates.some((t) => t.id === templateId);
    assert.ok(found, "Created template should appear in active templates list");
  });

  it("should return template in getActiveTemplatesByType for RPS", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Type Query Test",
    });
    const rpsTemplates =
      await sys.templates.read.getActiveTemplatesByType([0]); // RPS
    const found = rpsTemplates.some((t) => t.id === templateId);
    assert.ok(found, "Template should appear in RPS type query");
  });

  it("should emit TemplateCreated event", async () => {
    const conditions = encodeConditions(
      parseEther("10"),
      parseEther("100"),
      1n,
      15n
    );
    const rewardRules = encodeRewardRules(true, 95n);

    const hash = await sys.templates.write.createTemplate([
      "RPS Event Test",
      0,
      conditions,
      rewardRules,
      1,
      300,
      0,
      "0x0000000000000000000000000000000000000000000000000000000000000000" as `0x${string}`,
    ]);

    const receipt = await sys.publicClient.waitForTransactionReceipt({ hash });
    assert.ok(receipt.logs.length > 0, "Should emit at least one event");
    assert.equal(receipt.status, "success");
  });

  // ========================================================================
  // Activate / Deactivate
  // ========================================================================

  it("should deactivate a template", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Deactivate Test",
    });

    // Verify active
    let isActive = await sys.templates.read.isTemplateActive([templateId]);
    assert.ok(isActive);

    // Deactivate
    await sys.templates.write.deactivateTemplate([templateId]);

    isActive = await sys.templates.read.isTemplateActive([templateId]);
    assert.equal(isActive, false);
  });

  it("should re-activate a deactivated template", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Reactivate Test",
    });

    await sys.templates.write.deactivateTemplate([templateId]);
    assert.equal(
      await sys.templates.read.isTemplateActive([templateId]),
      false
    );

    await sys.templates.write.activateTemplate([templateId]);
    assert.equal(
      await sys.templates.read.isTemplateActive([templateId]),
      true
    );
  });

  it("should not list deactivated template in getActiveTemplates", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Deactivated List Test",
    });
    await sys.templates.write.deactivateTemplate([templateId]);

    const activeTemplates = await sys.templates.read.getActiveTemplates();
    const found = activeTemplates.some((t) => t.id === templateId);
    assert.equal(found, false, "Deactivated template should not be in active list");
  });

  // ========================================================================
  // Admin-only enforcement
  // ========================================================================

  it("should revert when non-admin tries to create template", async () => {
    const outsiderTemplates = await getContractAsUser(
      "ContractTemplates",
      sys.templates.address,
      sys.outsider.account.address
    );

    const conditions = encodeConditions(
      parseEther("10"),
      parseEther("100"),
      1n,
      15n
    );
    const rewardRules = encodeRewardRules(true, 95n);

    await assert.rejects(
      async () => {
        await outsiderTemplates.write.createTemplate([
          "RPS Outsider",
          0,
          conditions,
          rewardRules,
          1,
          300,
          0,
          "0x0000000000000000000000000000000000000000000000000000000000000000" as `0x${string}`,
        ]);
      },
      (err: any) => {
        // AccessControl revert
        return true;
      },
      "Non-admin should not be able to create templates"
    );
  });

  it("should revert when non-admin tries to deactivate template", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Admin Deactivate Guard",
    });

    const outsiderTemplates = await getContractAsUser(
      "ContractTemplates",
      sys.templates.address,
      sys.outsider.account.address
    );

    await assert.rejects(
      async () => {
        await outsiderTemplates.write.deactivateTemplate([templateId]);
      },
      (err: any) => true,
      "Non-admin should not be able to deactivate templates"
    );
  });

  it("should revert when non-admin tries to activate template", async () => {
    const templateId = await createRPSTemplate(sys, {
      name: "RPS Admin Activate Guard",
    });
    await sys.templates.write.deactivateTemplate([templateId]);

    const outsiderTemplates = await getContractAsUser(
      "ContractTemplates",
      sys.templates.address,
      sys.outsider.account.address
    );

    await assert.rejects(
      async () => {
        await outsiderTemplates.write.activateTemplate([templateId]);
      },
      (err: any) => true,
      "Non-admin should not be able to activate templates"
    );
  });

  // ========================================================================
  // Validation
  // ========================================================================

  it("should revert on duplicate template name", async () => {
    await createRPSTemplate(sys, { name: "RPS Unique Name" });

    await assert.rejects(
      async () => {
        await createRPSTemplate(sys, { name: "RPS Unique Name" });
      },
      (err: any) => true,
      "Duplicate template name should revert"
    );
  });

  it("should revert on fee rate above 5000 bps", async () => {
    const conditions = encodeConditions(
      parseEther("10"),
      parseEther("100"),
      1n,
      15n
    );
    const rewardRules = encodeRewardRules(true, 95n);

    await assert.rejects(
      async () => {
        await sys.templates.write.createTemplate([
          "RPS High Fee",
          0,
          conditions,
          rewardRules,
          1,
          5001, // above max
          0,
          "0x0000000000000000000000000000000000000000000000000000000000000000" as `0x${string}`,
        ]);
      },
      (err: any) => true,
      "Fee rate > 5000 bps should revert"
    );
  });
});
