/**
 * Test: Deployment — verifies all contracts deploy successfully,
 * roles are assigned correctly, and cross-references are set.
 */
import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import {
  deployFullSystem,
  type DeployedSystem,
  ADMIN_ROLE,
  SYSTEM_ROLE,
  OPERATOR_ROLE,
  CONTRACT_ROLE,
  SERVER_ROLE,
  SETTLER_ROLE,
  DEFAULT_ADMIN_ROLE,
} from "./helpers/deploy.js";

describe("Deployment", () => {
  let sys: DeployedSystem;

  before(async () => {
    sys = await deployFullSystem();
  });

  // ========================================================================
  // All contracts deploy successfully
  // ========================================================================

  it("should deploy MockIXToken with correct name and symbol", async () => {
    const name = await sys.token.read.name();
    const symbol = await sys.token.read.symbol();
    assert.equal(name, "IX Point");
    assert.equal(symbol, "IXP");
  });

  it("should deploy ContractTemplates at a non-zero address", async () => {
    assert.ok(sys.templates.address !== "0x0000000000000000000000000000000000000000");
  });

  it("should deploy ContractInstances at a non-zero address", async () => {
    assert.ok(sys.instances.address !== "0x0000000000000000000000000000000000000000");
  });

  it("should deploy ContractParties at a non-zero address", async () => {
    assert.ok(sys.parties.address !== "0x0000000000000000000000000000000000000000");
  });

  it("should deploy ContractResults at a non-zero address", async () => {
    assert.ok(sys.results.address !== "0x0000000000000000000000000000000000000000");
  });

  it("should deploy ContractConsents at a non-zero address", async () => {
    assert.ok(sys.consents.address !== "0x0000000000000000000000000000000000000000");
  });

  it("should deploy ContractSettlements at a non-zero address", async () => {
    assert.ok(sys.settlements.address !== "0x0000000000000000000000000000000000000000");
  });

  // ========================================================================
  // Roles assigned correctly
  // ========================================================================

  it("should grant ADMIN_ROLE on ContractTemplates to admin", async () => {
    const has = await sys.templates.read.hasRole([
      ADMIN_ROLE,
      sys.admin.account.address,
    ]);
    assert.ok(has);
  });

  it("should grant DEFAULT_ADMIN_ROLE on ContractTemplates to admin", async () => {
    const has = await sys.templates.read.hasRole([
      DEFAULT_ADMIN_ROLE,
      sys.admin.account.address,
    ]);
    assert.ok(has);
  });

  it("should grant SYSTEM_ROLE on ContractInstances to admin", async () => {
    const has = await sys.instances.read.hasRole([
      SYSTEM_ROLE,
      sys.admin.account.address,
    ]);
    assert.ok(has);
  });

  it("should grant SYSTEM_ROLE on ContractInstances to systemAccount", async () => {
    const has = await sys.instances.read.hasRole([
      SYSTEM_ROLE,
      sys.systemAccount.account.address,
    ]);
    assert.ok(has);
  });

  it("should grant CONTRACT_ROLE on ContractInstances to results", async () => {
    const has = await sys.instances.read.hasRole([
      CONTRACT_ROLE,
      sys.results.address,
    ]);
    assert.ok(has);
  });

  it("should grant CONTRACT_ROLE on ContractInstances to consents", async () => {
    const has = await sys.instances.read.hasRole([
      CONTRACT_ROLE,
      sys.consents.address,
    ]);
    assert.ok(has);
  });

  it("should grant CONTRACT_ROLE on ContractInstances to settlements", async () => {
    const has = await sys.instances.read.hasRole([
      CONTRACT_ROLE,
      sys.settlements.address,
    ]);
    assert.ok(has);
  });

  it("should grant CONTRACT_ROLE on ContractParties to settlements", async () => {
    const has = await sys.parties.read.hasRole([
      CONTRACT_ROLE,
      sys.settlements.address,
    ]);
    assert.ok(has);
  });

  it("should grant SERVER_ROLE on ContractResults to admin", async () => {
    const has = await sys.results.read.hasRole([
      SERVER_ROLE,
      sys.admin.account.address,
    ]);
    assert.ok(has);
  });

  it("should grant SERVER_ROLE on ContractConsents to admin", async () => {
    const has = await sys.consents.read.hasRole([
      SERVER_ROLE,
      sys.admin.account.address,
    ]);
    assert.ok(has);
  });

  it("should grant SETTLER_ROLE on ContractSettlements to admin", async () => {
    const has = await sys.settlements.read.hasRole([
      SETTLER_ROLE,
      sys.admin.account.address,
    ]);
    assert.ok(has);
  });

  it("should NOT grant ADMIN_ROLE to outsider on ContractTemplates", async () => {
    const has = await sys.templates.read.hasRole([
      ADMIN_ROLE,
      sys.outsider.account.address,
    ]);
    assert.equal(has, false);
  });

  // ========================================================================
  // Cross-references set correctly
  // ========================================================================

  it("should set treasury address on ContractSettlements", async () => {
    const treasuryAddr = await sys.settlements.read.getTreasury();
    assert.equal(
      treasuryAddr.toLowerCase(),
      sys.treasury.account.address.toLowerCase()
    );
  });
});
