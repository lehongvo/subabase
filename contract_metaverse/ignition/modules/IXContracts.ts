import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * IX Metaverse Contract System - Hardhat Ignition Deployment Module
 *
 * Deploys all 6 core contracts + MockIXToken, initializes them,
 * wires cross-contract references, and grants inter-contract roles.
 *
 * NOTE: All core contracts use `_disableInitializers()` in their constructor,
 * so `initialize()` must be called separately after deployment.
 * Since Hardhat Ignition deploys the implementation directly (no proxy),
 * we rely on the Foundry test pattern of resetting initialized state.
 * For production proxy deployments, use the deploy script instead.
 *
 * Treasury address uses the system UUID convention:
 * 0x0000000000000000000000000000000000000001
 */

const TREASURY_ADDRESS = "0x0000000000000000000000000000000000000001";

const IXContractsModule = buildModule("IXContracts", (m) => {
  // Deployer address (the account running the deployment)
  const deployer = m.getAccount(0);

  // Treasury address can be overridden via module parameter
  const treasury = m.getParameter("treasury", TREASURY_ADDRESS);

  // =========================================================================
  // Step 1: Deploy all contracts
  // =========================================================================

  const token = m.contract("MockIXToken", [], { id: "MockIXToken" });

  const templates = m.contract("ContractTemplates", [], {
    id: "ContractTemplates",
  });

  const instances = m.contract("ContractInstances", [], {
    id: "ContractInstances",
  });

  const parties = m.contract("ContractParties", [], {
    id: "ContractParties",
  });

  const results = m.contract("ContractResults", [], {
    id: "ContractResults",
  });

  const consents = m.contract("ContractConsents", [], {
    id: "ContractConsents",
  });

  const settlements = m.contract("ContractSettlements", [], {
    id: "ContractSettlements",
  });

  // =========================================================================
  // Step 2: Initialize all contracts
  // NOTE: These contracts use _disableInitializers() in their constructors.
  // In a proxy deployment, initialize() is called on the proxy, not the
  // implementation. For direct deployment (Ignition), initialize() will
  // revert because the implementation has already been locked.
  //
  // For MegaETH testnet deployment, use scripts/deploy-megaeth.ts instead,
  // which deploys via proxies or handles initialization correctly.
  // =========================================================================

  // Templates: initialize(admin)
  const initTemplates = m.call(templates, "initialize", [deployer], {
    id: "initTemplates",
  });

  // Instances: initialize(admin, templatesAddress)
  const initInstances = m.call(instances, "initialize", [deployer, templates], {
    id: "initInstances",
    after: [initTemplates],
  });

  // Parties: initialize(admin, instancesAddress, tokenAddress)
  const initParties = m.call(parties, "initialize", [deployer, instances, token], {
    id: "initParties",
    after: [initInstances],
  });

  // Results: initialize(defaultAdmin, instancesContract)
  const initResults = m.call(results, "initialize", [deployer, instances], {
    id: "initResults",
    after: [initInstances],
  });

  // Consents: initialize(defaultAdmin, instancesContract, partiesContract, templatesContract)
  const initConsents = m.call(
    consents,
    "initialize",
    [deployer, instances, parties, templates],
    {
      id: "initConsents",
      after: [initInstances, initParties],
    }
  );

  // Settlements: initialize(defaultAdmin, instancesContract, partiesContract,
  //                          resultsContract, consentsContract, treasury)
  const initSettlements = m.call(
    settlements,
    "initialize",
    [deployer, instances, parties, results, consents, treasury],
    {
      id: "initSettlements",
      after: [initInstances, initParties, initResults, initConsents],
    }
  );

  // =========================================================================
  // Step 3: Wire cross-contract references
  // =========================================================================

  // Instances needs references to parties, results, consents, settlements
  const setInstancesParties = m.call(
    instances,
    "setPartiesContract",
    [parties],
    { id: "setInstancesParties", after: [initInstances, initParties] }
  );

  const setInstancesResults = m.call(
    instances,
    "setResultsContract",
    [results],
    { id: "setInstancesResults", after: [initInstances, initResults] }
  );

  const setInstancesConsents = m.call(
    instances,
    "setConsentsContract",
    [consents],
    { id: "setInstancesConsents", after: [initInstances, initConsents] }
  );

  const setInstancesSettlements = m.call(
    instances,
    "setSettlementsContract",
    [settlements],
    { id: "setInstancesSettlements", after: [initInstances, initSettlements] }
  );

  // Parties needs templates reference for bet range validation
  const setPartiesTemplates = m.call(
    parties,
    "setTemplatesContract",
    [templates],
    { id: "setPartiesTemplates", after: [initParties, initTemplates] }
  );

  // Settlements needs templates reference for fee rate lookup
  const setSettlementsTemplates = m.call(
    settlements,
    "setTemplatesContract",
    [templates],
    { id: "setSettlementsTemplates", after: [initSettlements, initTemplates] }
  );

  // =========================================================================
  // Step 4: Grant CONTRACT_ROLE for inter-contract calls
  // CONTRACT_ROLE = keccak256("CONTRACT_ROLE")
  // =========================================================================

  const CONTRACT_ROLE =
    "0x364d3d7565c7a8300c96fd53e065d19b65848d7b23b3191adcd55621c744e71b";

  // Results -> Instances (completeInstance)
  m.call(instances, "grantRole", [CONTRACT_ROLE, results], {
    id: "grantContractRoleResultsOnInstances",
    after: [initInstances, initResults],
  });

  // Consents -> Instances (disputeInstance)
  m.call(instances, "grantRole", [CONTRACT_ROLE, consents], {
    id: "grantContractRoleConsentsOnInstances",
    after: [initInstances, initConsents],
  });

  // Settlements -> Instances (settleInstance)
  m.call(instances, "grantRole", [CONTRACT_ROLE, settlements], {
    id: "grantContractRoleSettlementsOnInstances",
    after: [initInstances, initSettlements],
  });

  // Settlements -> Parties (releaseEscrow, refundEscrow)
  m.call(parties, "grantRole", [CONTRACT_ROLE, settlements], {
    id: "grantContractRoleSettlementsOnParties",
    after: [initParties, initSettlements],
  });

  // =========================================================================
  // Return all deployed contracts
  // =========================================================================

  return {
    token,
    templates,
    instances,
    parties,
    results,
    consents,
    settlements,
  };
});

export default IXContractsModule;
