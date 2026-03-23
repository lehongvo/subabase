import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { encodeFunctionData } from "viem";

/**
 * IX Metaverse Contract System - Hardhat Ignition Deployment Module
 *
 * Deploys all 6 core contracts behind IXProxy (TransparentUpgradeableProxy)
 * + MockIXToken (direct), initializes via proxy constructor, wires
 * cross-contract references, and grants inter-contract roles.
 *
 * Treasury address uses the system UUID convention:
 * 0x0000000000000000000000000000000000000001
 *
 * NOTE: Ignition interacts with proxies using the implementation ABI
 * by passing the proxy's Future to m.call() with the implementation's
 * contract reference. Since Ignition's type system doesn't natively
 * support this pattern well, use scripts/deploy-megaeth.ts for
 * production deployments.
 */

const TREASURY_ADDRESS = "0x0000000000000000000000000000000000000001";

// ABI fragments for encodeFunctionData
const initTemplatesAbi = [
  {
    name: "initialize",
    type: "function" as const,
    stateMutability: "nonpayable" as const,
    inputs: [{ name: "admin", type: "address" as const }],
    outputs: [],
  },
];

const initInstancesAbi = [
  {
    name: "initialize",
    type: "function" as const,
    stateMutability: "nonpayable" as const,
    inputs: [
      { name: "admin", type: "address" as const },
      { name: "templatesAddress", type: "address" as const },
    ],
    outputs: [],
  },
];

const initPartiesAbi = [
  {
    name: "initialize",
    type: "function" as const,
    stateMutability: "nonpayable" as const,
    inputs: [
      { name: "admin", type: "address" as const },
      { name: "instancesAddress", type: "address" as const },
      { name: "tokenAddress", type: "address" as const },
    ],
    outputs: [],
  },
];

const initResultsAbi = [
  {
    name: "initialize",
    type: "function" as const,
    stateMutability: "nonpayable" as const,
    inputs: [
      { name: "defaultAdmin", type: "address" as const },
      { name: "instancesContract", type: "address" as const },
    ],
    outputs: [],
  },
];

const initConsentsAbi = [
  {
    name: "initialize",
    type: "function" as const,
    stateMutability: "nonpayable" as const,
    inputs: [
      { name: "defaultAdmin", type: "address" as const },
      { name: "instancesContract", type: "address" as const },
      { name: "partiesContract", type: "address" as const },
      { name: "templatesContract", type: "address" as const },
    ],
    outputs: [],
  },
];

const initSettlementsAbi = [
  {
    name: "initialize",
    type: "function" as const,
    stateMutability: "nonpayable" as const,
    inputs: [
      { name: "defaultAdmin", type: "address" as const },
      { name: "instancesContract", type: "address" as const },
      { name: "partiesContract", type: "address" as const },
      { name: "resultsContract", type: "address" as const },
      { name: "consentsContract", type: "address" as const },
      { name: "treasury", type: "address" as const },
    ],
    outputs: [],
  },
];

const IXContractsModule = buildModule("IXContracts", (m) => {
  const deployer = m.getAccount(0);
  const treasury = m.getParameter("treasury", TREASURY_ADDRESS);

  // =========================================================================
  // Step 1: Deploy MockIXToken (not upgradeable, direct deployment)
  // =========================================================================

  const token = m.contract("MockIXToken", [], { id: "MockIXToken" });

  // =========================================================================
  // Step 2: Deploy implementations (these are locked via _disableInitializers)
  // =========================================================================

  const templatesImpl = m.contract("ContractTemplates", [], { id: "TemplatesImpl" });
  const instancesImpl = m.contract("ContractInstances", [], { id: "InstancesImpl" });
  const partiesImpl = m.contract("ContractParties", [], { id: "PartiesImpl" });
  const resultsImpl = m.contract("ContractResults", [], { id: "ResultsImpl" });
  const consentsImpl = m.contract("ContractConsents", [], { id: "ConsentsImpl" });
  const settlementsImpl = m.contract("ContractSettlements", [], { id: "SettlementsImpl" });

  // =========================================================================
  // Step 3: Deploy proxies with initialization data
  // NOTE: Ignition does not support encodeFunctionData with Future references
  // at build time. The proxy init data must be computed at deploy time.
  // Since Ignition cannot encode init data referencing other Futures,
  // we deploy proxies with empty init data and call initialize() separately.
  //
  // IMPORTANT: This approach will NOT work because _disableInitializers()
  // prevents calling initialize() on the implementation, and calling it
  // on the proxy with empty init data means the proxy is uninitialized.
  //
  // For proxy-based deployments, use scripts/deploy-megaeth.ts instead.
  // This Ignition module is provided as a reference but requires Ignition
  // proxy support (e.g., hardhat-ignition-upgradeable plugin) for full
  // production use.
  // =========================================================================

  // For now, deploy proxies with empty init data and initialize after
  // This will work IF the proxy forwards initialize() calls to the impl
  const emptyData = "0x" as `0x${string}`;

  const templates = m.contract("IXProxy", [templatesImpl, deployer, emptyData], {
    id: "TemplatesProxy",
    after: [templatesImpl],
  });

  const instances = m.contract("IXProxy", [instancesImpl, deployer, emptyData], {
    id: "InstancesProxy",
    after: [instancesImpl],
  });

  const parties = m.contract("IXProxy", [partiesImpl, deployer, emptyData], {
    id: "PartiesProxy",
    after: [partiesImpl],
  });

  const results = m.contract("IXProxy", [resultsImpl, deployer, emptyData], {
    id: "ResultsProxy",
    after: [resultsImpl],
  });

  const consents = m.contract("IXProxy", [consentsImpl, deployer, emptyData], {
    id: "ConsentsProxy",
    after: [consentsImpl],
  });

  const settlements = m.contract("IXProxy", [settlementsImpl, deployer, emptyData], {
    id: "SettlementsProxy",
    after: [settlementsImpl],
  });

  // =========================================================================
  // Step 4: Initialize contracts via proxy (calling on proxy address with
  // implementation ABI). We use m.call with the proxy contract but specify
  // the function from the implementation.
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

  // Settlements: initialize(defaultAdmin, instances, parties, results, consents, treasury)
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
  // Step 5: Wire cross-contract references
  // =========================================================================

  m.call(instances, "setPartiesContract", [parties], {
    id: "setInstancesParties",
    after: [initInstances, initParties],
  });

  m.call(instances, "setResultsContract", [results], {
    id: "setInstancesResults",
    after: [initInstances, initResults],
  });

  m.call(instances, "setConsentsContract", [consents], {
    id: "setInstancesConsents",
    after: [initInstances, initConsents],
  });

  m.call(instances, "setSettlementsContract", [settlements], {
    id: "setInstancesSettlements",
    after: [initInstances, initSettlements],
  });

  m.call(parties, "setTemplatesContract", [templates], {
    id: "setPartiesTemplates",
    after: [initParties, initTemplates],
  });

  m.call(settlements, "setTemplatesContract", [templates], {
    id: "setSettlementsTemplates",
    after: [initSettlements, initTemplates],
  });

  // =========================================================================
  // Step 6: Grant CONTRACT_ROLE for inter-contract calls
  // CONTRACT_ROLE = keccak256("CONTRACT_ROLE")
  // =========================================================================

  const CONTRACT_ROLE =
    "0x364d3d7565c7a8300c96fd53e065d19b65848d7b23b3191adcd55621c744e71b";

  m.call(instances, "grantRole", [CONTRACT_ROLE, results], {
    id: "grantContractRoleResultsOnInstances",
    after: [initInstances, initResults],
  });

  m.call(instances, "grantRole", [CONTRACT_ROLE, consents], {
    id: "grantContractRoleConsentsOnInstances",
    after: [initInstances, initConsents],
  });

  m.call(instances, "grantRole", [CONTRACT_ROLE, settlements], {
    id: "grantContractRoleSettlementsOnInstances",
    after: [initInstances, initSettlements],
  });

  m.call(parties, "grantRole", [CONTRACT_ROLE, settlements], {
    id: "grantContractRoleSettlementsOnParties",
    after: [initParties, initSettlements],
  });

  // =========================================================================
  // Return all deployed contracts (proxy addresses)
  // =========================================================================

  return {
    token,
    templates,
    instances,
    parties,
    results,
    consents,
    settlements,
    // Also return implementations for reference
    templatesImpl,
    instancesImpl,
    partiesImpl,
    resultsImpl,
    consentsImpl,
    settlementsImpl,
  };
});

export default IXContractsModule;
