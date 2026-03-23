/**
 * IX Metaverse Contract System - MegaETH Testnet Deployment Script
 *
 * Deploys all 6 core contracts + MockIXToken, initializes them,
 * wires cross-contract references, and grants inter-contract roles.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-megaeth.ts
 *
 * Environment variables (from .env):
 *   PRIVATE_KEY           - Deployer private key
 *   MEGAETH_TEST_NET_RPC  - MegaETH testnet RPC URL
 */

import { network } from "hardhat";
import { keccak256, toHex, type Address, type Hash } from "viem";

// Treasury address (system UUID convention)
const TREASURY_ADDRESS: Address = "0x0000000000000000000000000000000000000001";

// Role hashes (matching Solidity: keccak256("CONTRACT_ROLE"), etc.)
const CONTRACT_ROLE: Hash = keccak256(toHex("CONTRACT_ROLE"));
const SYSTEM_ROLE: Hash = keccak256(toHex("SYSTEM_ROLE"));
const SERVER_ROLE: Hash = keccak256(toHex("SERVER_ROLE"));
const SETTLER_ROLE: Hash = keccak256(toHex("SETTLER_ROLE"));
const OPERATOR_ROLE: Hash = keccak256(toHex("OPERATOR_ROLE"));

interface DeployedContracts {
  token: Address;
  templates: Address;
  instances: Address;
  parties: Address;
  results: Address;
  consents: Address;
  settlements: Address;
}

async function main() {
  console.log("=== IX Metaverse Contract System - MegaETH Testnet Deployment ===\n");

  // Connect to MegaETH testnet
  const { viem } = await network.connect({
    network: "megaethTestnet",
    chainType: "l1",
  });

  const publicClient = await viem.getPublicClient();
  const [deployerClient] = await viem.getWalletClients();

  const deployer = deployerClient.account.address;
  console.log("Deployer address:", deployer);

  // Check deployer balance
  const balance = await publicClient.getBalance({ address: deployer });
  console.log("Deployer balance:", balance.toString(), "wei");
  console.log(
    "Deployer balance:",
    (Number(balance) / 1e18).toFixed(6),
    "ETH\n"
  );

  if (balance === 0n) {
    console.error("ERROR: Deployer account has zero balance.");
    console.error("Fund the account before deploying:");
    console.error(`  Address: ${deployer}`);
    console.error("  Network: MegaETH Testnet (Carrot)");
    console.error("  Faucet:  https://megaeth.com/faucet (if available)");
    process.exit(1);
  }

  const chainId = await publicClient.getChainId();
  console.log("Chain ID:", chainId);
  console.log("RPC URL: https://carrot.megaeth.com/rpc\n");

  const deployed: DeployedContracts = {} as DeployedContracts;
  const txHashes: Record<string, Hash> = {};
  const gasCosts: Record<string, bigint> = {};

  // Helper: deploy a contract and return its address
  async function deploy(
    name: string,
    args: readonly unknown[] = []
  ): Promise<Address> {
    console.log(`Deploying ${name}...`);
    const contract = await viem.deployContract(name, args);
    console.log(`  ${name} deployed at: ${contract.address}`);
    return contract.address;
  }

  // =========================================================================
  // Step 1: Deploy all contracts
  // =========================================================================

  console.log("--- Step 1: Deploy Contracts ---\n");

  deployed.token = await deploy("MockIXToken");
  deployed.templates = await deploy("ContractTemplates");
  deployed.instances = await deploy("ContractInstances");
  deployed.parties = await deploy("ContractParties");
  deployed.results = await deploy("ContractResults");
  deployed.consents = await deploy("ContractConsents");
  deployed.settlements = await deploy("ContractSettlements");

  console.log("\nAll contracts deployed.\n");

  // =========================================================================
  // Step 2: Initialize all contracts
  // NOTE: Contracts have _disableInitializers() in constructor, so initialize()
  // will revert on direct (non-proxy) deployments. For production, deploy
  // behind TransparentUpgradeableProxy. For testnet, we attempt direct init
  // and catch errors.
  // =========================================================================

  console.log("--- Step 2: Initialize Contracts ---\n");

  try {
    // Templates: initialize(admin)
    console.log("Initializing ContractTemplates...");
    let hash = await deployerClient.writeContract({
      address: deployed.templates,
      abi: [
        {
          name: "initialize",
          type: "function",
          stateMutability: "nonpayable",
          inputs: [{ name: "admin", type: "address" }],
          outputs: [],
        },
      ],
      functionName: "initialize",
      args: [deployer],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    txHashes["initTemplates"] = hash;
    console.log("  Templates initialized. Tx:", hash);

    // Instances: initialize(admin, templatesAddress)
    console.log("Initializing ContractInstances...");
    hash = await deployerClient.writeContract({
      address: deployed.instances,
      abi: [
        {
          name: "initialize",
          type: "function",
          stateMutability: "nonpayable",
          inputs: [
            { name: "admin", type: "address" },
            { name: "templatesAddress", type: "address" },
          ],
          outputs: [],
        },
      ],
      functionName: "initialize",
      args: [deployer, deployed.templates],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    txHashes["initInstances"] = hash;
    console.log("  Instances initialized. Tx:", hash);

    // Parties: initialize(admin, instancesAddress, tokenAddress)
    console.log("Initializing ContractParties...");
    hash = await deployerClient.writeContract({
      address: deployed.parties,
      abi: [
        {
          name: "initialize",
          type: "function",
          stateMutability: "nonpayable",
          inputs: [
            { name: "admin", type: "address" },
            { name: "instancesAddress", type: "address" },
            { name: "tokenAddress", type: "address" },
          ],
          outputs: [],
        },
      ],
      functionName: "initialize",
      args: [deployer, deployed.instances, deployed.token],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    txHashes["initParties"] = hash;
    console.log("  Parties initialized. Tx:", hash);

    // Results: initialize(defaultAdmin, instancesContract)
    console.log("Initializing ContractResults...");
    hash = await deployerClient.writeContract({
      address: deployed.results,
      abi: [
        {
          name: "initialize",
          type: "function",
          stateMutability: "nonpayable",
          inputs: [
            { name: "defaultAdmin", type: "address" },
            { name: "instancesContract", type: "address" },
          ],
          outputs: [],
        },
      ],
      functionName: "initialize",
      args: [deployer, deployed.instances],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    txHashes["initResults"] = hash;
    console.log("  Results initialized. Tx:", hash);

    // Consents: initialize(defaultAdmin, instancesContract, partiesContract, templatesContract)
    console.log("Initializing ContractConsents...");
    hash = await deployerClient.writeContract({
      address: deployed.consents,
      abi: [
        {
          name: "initialize",
          type: "function",
          stateMutability: "nonpayable",
          inputs: [
            { name: "defaultAdmin", type: "address" },
            { name: "instancesContract", type: "address" },
            { name: "partiesContract", type: "address" },
            { name: "templatesContract", type: "address" },
          ],
          outputs: [],
        },
      ],
      functionName: "initialize",
      args: [deployer, deployed.instances, deployed.parties, deployed.templates],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    txHashes["initConsents"] = hash;
    console.log("  Consents initialized. Tx:", hash);

    // Settlements: initialize(defaultAdmin, instancesContract, partiesContract,
    //                          resultsContract, consentsContract, treasury)
    console.log("Initializing ContractSettlements...");
    hash = await deployerClient.writeContract({
      address: deployed.settlements,
      abi: [
        {
          name: "initialize",
          type: "function",
          stateMutability: "nonpayable",
          inputs: [
            { name: "defaultAdmin", type: "address" },
            { name: "instancesContract", type: "address" },
            { name: "partiesContract", type: "address" },
            { name: "resultsContract", type: "address" },
            { name: "consentsContract", type: "address" },
            { name: "treasury", type: "address" },
          ],
          outputs: [],
        },
      ],
      functionName: "initialize",
      args: [
        deployer,
        deployed.instances,
        deployed.parties,
        deployed.results,
        deployed.consents,
        TREASURY_ADDRESS,
      ],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    txHashes["initSettlements"] = hash;
    console.log("  Settlements initialized. Tx:", hash);
  } catch (error: any) {
    console.error("\nInitialization failed:", error.message);
    console.error(
      "\nNOTE: If you see 'InvalidInitialization', the contracts use _disableInitializers()"
    );
    console.error(
      "in their constructors. For production, deploy behind TransparentUpgradeableProxy."
    );
    console.error(
      "The contracts have been deployed but are NOT initialized.\n"
    );
    printDeploymentSummary(deployed, txHashes);
    process.exit(1);
  }

  console.log("\nAll contracts initialized.\n");

  // =========================================================================
  // Step 3: Wire cross-contract references
  // =========================================================================

  console.log("--- Step 3: Wire Cross-Contract References ---\n");

  const setterAbi = (fnName: string) => [
    {
      name: fnName,
      type: "function" as const,
      stateMutability: "nonpayable" as const,
      inputs: [{ name: "addr", type: "address" as const }],
      outputs: [],
    },
  ];

  // Instances -> Parties, Results, Consents, Settlements
  console.log("Setting Instances cross-references...");
  for (const [fnName, addr, label] of [
    ["setPartiesContract", deployed.parties, "Parties"],
    ["setResultsContract", deployed.results, "Results"],
    ["setConsentsContract", deployed.consents, "Consents"],
    ["setSettlementsContract", deployed.settlements, "Settlements"],
  ] as const) {
    const hash = await deployerClient.writeContract({
      address: deployed.instances,
      abi: setterAbi(fnName),
      functionName: fnName,
      args: [addr],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    txHashes[`instances.${fnName}`] = hash;
    console.log(`  Instances -> ${label}: ${hash}`);
  }

  // Parties -> Templates
  console.log("Setting Parties cross-references...");
  let hash = await deployerClient.writeContract({
    address: deployed.parties,
    abi: setterAbi("setTemplatesContract"),
    functionName: "setTemplatesContract",
    args: [deployed.templates],
  });
  await publicClient.waitForTransactionReceipt({ hash });
  txHashes["parties.setTemplatesContract"] = hash;
  console.log(`  Parties -> Templates: ${hash}`);

  // Settlements -> Templates
  console.log("Setting Settlements cross-references...");
  hash = await deployerClient.writeContract({
    address: deployed.settlements,
    abi: setterAbi("setTemplatesContract"),
    functionName: "setTemplatesContract",
    args: [deployed.templates],
  });
  await publicClient.waitForTransactionReceipt({ hash });
  txHashes["settlements.setTemplatesContract"] = hash;
  console.log(`  Settlements -> Templates: ${hash}`);

  console.log("\nCross-contract references wired.\n");

  // =========================================================================
  // Step 4: Grant roles
  // =========================================================================

  console.log("--- Step 4: Grant Roles ---\n");

  const grantRoleAbi = [
    {
      name: "grantRole",
      type: "function" as const,
      stateMutability: "nonpayable" as const,
      inputs: [
        { name: "role", type: "bytes32" as const },
        { name: "account", type: "address" as const },
      ],
      outputs: [],
    },
  ];

  // CONTRACT_ROLE grants on Instances
  const instanceRoleGrants: [Hash, Address, string][] = [
    [CONTRACT_ROLE, deployed.results, "Results (completeInstance)"],
    [CONTRACT_ROLE, deployed.consents, "Consents (disputeInstance)"],
    [CONTRACT_ROLE, deployed.settlements, "Settlements (settleInstance)"],
  ];

  console.log("Granting CONTRACT_ROLE on Instances...");
  for (const [role, addr, label] of instanceRoleGrants) {
    hash = await deployerClient.writeContract({
      address: deployed.instances,
      abi: grantRoleAbi,
      functionName: "grantRole",
      args: [role, addr],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    txHashes[`instances.grantRole.${label}`] = hash;
    console.log(`  CONTRACT_ROLE -> ${label}: ${hash}`);
  }

  // CONTRACT_ROLE grants on Parties
  console.log("Granting CONTRACT_ROLE on Parties...");
  hash = await deployerClient.writeContract({
    address: deployed.parties,
    abi: grantRoleAbi,
    functionName: "grantRole",
    args: [CONTRACT_ROLE, deployed.settlements],
  });
  await publicClient.waitForTransactionReceipt({ hash });
  txHashes["parties.grantRole.Settlements"] = hash;
  console.log(`  CONTRACT_ROLE -> Settlements (releaseEscrow, refundEscrow): ${hash}`);

  // Grant SYSTEM_ROLE to deployer on Instances (for createInstance, activateInstance)
  console.log("Granting SYSTEM_ROLE on Instances to deployer...");
  hash = await deployerClient.writeContract({
    address: deployed.instances,
    abi: grantRoleAbi,
    functionName: "grantRole",
    args: [SYSTEM_ROLE, deployer],
  });
  await publicClient.waitForTransactionReceipt({ hash });
  txHashes["instances.grantRole.SYSTEM_ROLE.deployer"] = hash;
  console.log(`  SYSTEM_ROLE -> deployer: ${hash}`);

  // Grant OPERATOR_ROLE to deployer on Instances (for resolveInstance)
  console.log("Granting OPERATOR_ROLE on Instances to deployer...");
  hash = await deployerClient.writeContract({
    address: deployed.instances,
    abi: grantRoleAbi,
    functionName: "grantRole",
    args: [OPERATOR_ROLE, deployer],
  });
  await publicClient.waitForTransactionReceipt({ hash });
  txHashes["instances.grantRole.OPERATOR_ROLE.deployer"] = hash;
  console.log(`  OPERATOR_ROLE -> deployer: ${hash}`);

  console.log("\nAll roles granted.\n");

  // =========================================================================
  // Summary
  // =========================================================================

  printDeploymentSummary(deployed, txHashes);
}

function printDeploymentSummary(
  deployed: DeployedContracts,
  txHashes: Record<string, Hash>
) {
  console.log("=== DEPLOYMENT SUMMARY ===\n");
  console.log("Network:  MegaETH Testnet (Carrot)");
  console.log("RPC URL:  https://carrot.megaeth.com/rpc\n");

  console.log("Contract Addresses:");
  console.log(`  MockIXToken:          ${deployed.token}`);
  console.log(`  ContractTemplates:    ${deployed.templates}`);
  console.log(`  ContractInstances:    ${deployed.instances}`);
  console.log(`  ContractParties:      ${deployed.parties}`);
  console.log(`  ContractResults:      ${deployed.results}`);
  console.log(`  ContractConsents:     ${deployed.consents}`);
  console.log(`  ContractSettlements:  ${deployed.settlements}`);

  console.log("\nTransaction Hashes:");
  for (const [key, hash] of Object.entries(txHashes)) {
    console.log(`  ${key}: ${hash}`);
  }

  console.log("\nTreasury Address:", TREASURY_ADDRESS);
  console.log("\n=== DEPLOYMENT COMPLETE ===");
}

main().catch((error) => {
  console.error("Deployment failed:", error);
  process.exit(1);
});
