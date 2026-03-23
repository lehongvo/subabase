/**
 * IX Metaverse Contract System - MegaETH Testnet Deployment Script
 *
 * Deploys all 6 core contracts behind TransparentUpgradeableProxy + MockIXToken,
 * initializes them, wires cross-contract references, and grants inter-contract roles.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-megaeth.ts
 *
 * Environment variables (from .env via dotenv):
 *   PRIVATE_KEY           - Deployer private key
 *   MEGAETH_TEST_NET_RPC  - MegaETH testnet RPC URL
 */

import { network } from "hardhat";
import {
  keccak256,
  toHex,
  encodeFunctionData,
  type Address,
  type Hash,
  type Abi,
} from "viem";

// Treasury address (system UUID convention)
const TREASURY_ADDRESS: Address = "0x0000000000000000000000000000000000000001";

// Role hashes (matching Solidity: keccak256("..."))
const CONTRACT_ROLE: Hash = keccak256(toHex("CONTRACT_ROLE"));
const SYSTEM_ROLE: Hash = keccak256(toHex("SYSTEM_ROLE"));
const OPERATOR_ROLE: Hash = keccak256(toHex("OPERATOR_ROLE"));

// ABI fragments for initialize functions
const initTemplatesAbi = [
  {
    name: "initialize",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "admin", type: "address" }],
    outputs: [],
  },
] as const;

const initInstancesAbi = [
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
] as const;

const initPartiesAbi = [
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
] as const;

const initResultsAbi = [
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
] as const;

const initConsentsAbi = [
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
] as const;

const initSettlementsAbi = [
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
] as const;

const setterAbi = (fnName: string): Abi => [
  {
    name: fnName,
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "addr", type: "address" }],
    outputs: [],
  },
];

const grantRoleAbi: Abi = [
  {
    name: "grantRole",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "role", type: "bytes32" },
      { name: "account", type: "address" },
    ],
    outputs: [],
  },
];

interface DeployedContracts {
  tokenImpl: Address;
  templatesImpl: Address;
  instancesImpl: Address;
  partiesImpl: Address;
  resultsImpl: Address;
  consentsImpl: Address;
  settlementsImpl: Address;
  // Proxy addresses (use these for interactions)
  token: Address;
  templates: Address;
  instances: Address;
  parties: Address;
  results: Address;
  consents: Address;
  settlements: Address;
}

async function main() {
  console.log(
    "=== IX Metaverse Contract System - MegaETH Testnet Deployment ===\n"
  );

  const { viem } = await network.connect({
    network: "megaethTestnet",
    chainType: "l1",
  });

  const publicClient = await viem.getPublicClient();
  const [deployerClient] = await viem.getWalletClients();

  const deployer = deployerClient.account.address;
  console.log("Deployer address:", deployer);

  const balance = await publicClient.getBalance({ address: deployer });
  console.log(
    "Deployer balance:",
    (Number(balance) / 1e18).toFixed(6),
    "ETH\n"
  );

  if (balance === 0n) {
    console.error("ERROR: Deployer account has zero balance.");
    console.error(`Fund address ${deployer} on MegaETH Testnet (Carrot).`);
    process.exit(1);
  }

  const chainId = await publicClient.getChainId();
  console.log("Chain ID:", chainId);
  console.log("RPC URL: https://carrot.megaeth.com/rpc\n");

  const deployed: DeployedContracts = {} as any;
  const txHashes: Record<string, Hash> = {};

  // =========================================================================
  // Helper: deploy implementation + TransparentUpgradeableProxy
  // The proxy constructor calls initialize() atomically via _data param.
  // =========================================================================

  async function deployWithProxy(
    contractName: string,
    initData: `0x${string}`
  ): Promise<{ impl: Address; proxy: Address }> {
    console.log(`  Deploying ${contractName} implementation...`);
    const impl = await viem.deployContract(contractName);
    console.log(`    Implementation: ${impl.address}`);

    console.log(`  Deploying IXProxy (TransparentUpgradeableProxy) for ${contractName}...`);
    const proxy = await viem.deployContract(
      "IXProxy" as any,
      [impl.address, deployer, initData] as any
    );
    console.log(`    Proxy: ${proxy.address}`);

    return { impl: impl.address, proxy: proxy.address };
  }

  // =========================================================================
  // Step 1: Deploy MockIXToken (not upgradeable)
  // =========================================================================

  console.log("--- Step 1: Deploy MockIXToken ---\n");
  const tokenContract = await viem.deployContract("MockIXToken");
  deployed.token = tokenContract.address;
  deployed.tokenImpl = tokenContract.address;
  console.log(`  MockIXToken: ${deployed.token}\n`);

  // =========================================================================
  // Step 2: Deploy core contracts with proxies + initialization
  // =========================================================================

  console.log("--- Step 2: Deploy Core Contracts with Proxies ---\n");

  // 2a. ContractTemplates
  console.log("[1/6] ContractTemplates");
  const tmpl = await deployWithProxy(
    "ContractTemplates",
    encodeFunctionData({
      abi: initTemplatesAbi,
      functionName: "initialize",
      args: [deployer],
    })
  );
  deployed.templatesImpl = tmpl.impl;
  deployed.templates = tmpl.proxy;
  console.log();

  // 2b. ContractInstances
  console.log("[2/6] ContractInstances");
  const inst = await deployWithProxy(
    "ContractInstances",
    encodeFunctionData({
      abi: initInstancesAbi,
      functionName: "initialize",
      args: [deployer, deployed.templates],
    })
  );
  deployed.instancesImpl = inst.impl;
  deployed.instances = inst.proxy;
  console.log();

  // 2c. ContractParties
  console.log("[3/6] ContractParties");
  const part = await deployWithProxy(
    "ContractParties",
    encodeFunctionData({
      abi: initPartiesAbi,
      functionName: "initialize",
      args: [deployer, deployed.instances, deployed.token],
    })
  );
  deployed.partiesImpl = part.impl;
  deployed.parties = part.proxy;
  console.log();

  // 2d. ContractResults
  console.log("[4/6] ContractResults");
  const res = await deployWithProxy(
    "ContractResults",
    encodeFunctionData({
      abi: initResultsAbi,
      functionName: "initialize",
      args: [deployer, deployed.instances],
    })
  );
  deployed.resultsImpl = res.impl;
  deployed.results = res.proxy;
  console.log();

  // 2e. ContractConsents
  console.log("[5/6] ContractConsents");
  const cons = await deployWithProxy(
    "ContractConsents",
    encodeFunctionData({
      abi: initConsentsAbi,
      functionName: "initialize",
      args: [deployer, deployed.instances, deployed.parties, deployed.templates],
    })
  );
  deployed.consentsImpl = cons.impl;
  deployed.consents = cons.proxy;
  console.log();

  // 2f. ContractSettlements
  console.log("[6/6] ContractSettlements");
  const sett = await deployWithProxy(
    "ContractSettlements",
    encodeFunctionData({
      abi: initSettlementsAbi,
      functionName: "initialize",
      args: [
        deployer,
        deployed.instances,
        deployed.parties,
        deployed.results,
        deployed.consents,
        TREASURY_ADDRESS,
      ],
    })
  );
  deployed.settlementsImpl = sett.impl;
  deployed.settlements = sett.proxy;
  console.log();

  console.log("All contracts deployed and initialized via proxies.\n");

  // =========================================================================
  // Step 3: Wire cross-contract references
  // =========================================================================

  console.log("--- Step 3: Wire Cross-Contract References ---\n");

  async function callSetter(
    target: Address,
    fnName: string,
    value: Address,
    label: string
  ) {
    const hash = await deployerClient.writeContract({
      address: target,
      abi: setterAbi(fnName),
      functionName: fnName,
      args: [value],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    txHashes[label] = hash;
    console.log(`  ${label}: ${hash}`);
  }

  await callSetter(deployed.instances, "setPartiesContract", deployed.parties, "instances.setPartiesContract");
  await callSetter(deployed.instances, "setResultsContract", deployed.results, "instances.setResultsContract");
  await callSetter(deployed.instances, "setConsentsContract", deployed.consents, "instances.setConsentsContract");
  await callSetter(deployed.instances, "setSettlementsContract", deployed.settlements, "instances.setSettlementsContract");
  await callSetter(deployed.parties, "setTemplatesContract", deployed.templates, "parties.setTemplatesContract");
  await callSetter(deployed.settlements, "setTemplatesContract", deployed.templates, "settlements.setTemplatesContract");

  console.log("\nCross-contract references wired.\n");

  // =========================================================================
  // Step 4: Grant roles
  // =========================================================================

  console.log("--- Step 4: Grant Roles ---\n");

  async function grantRole(
    target: Address,
    role: Hash,
    account: Address,
    label: string
  ) {
    const hash = await deployerClient.writeContract({
      address: target,
      abi: grantRoleAbi,
      functionName: "grantRole",
      args: [role, account],
    });
    await publicClient.waitForTransactionReceipt({ hash });
    txHashes[label] = hash;
    console.log(`  ${label}: ${hash}`);
  }

  // CONTRACT_ROLE on Instances
  await grantRole(deployed.instances, CONTRACT_ROLE, deployed.results, "instances.CONTRACT_ROLE -> Results");
  await grantRole(deployed.instances, CONTRACT_ROLE, deployed.consents, "instances.CONTRACT_ROLE -> Consents");
  await grantRole(deployed.instances, CONTRACT_ROLE, deployed.settlements, "instances.CONTRACT_ROLE -> Settlements");

  // CONTRACT_ROLE on Parties
  await grantRole(deployed.parties, CONTRACT_ROLE, deployed.settlements, "parties.CONTRACT_ROLE -> Settlements");

  // SYSTEM_ROLE and OPERATOR_ROLE on Instances for deployer
  await grantRole(deployed.instances, SYSTEM_ROLE, deployer, "instances.SYSTEM_ROLE -> deployer");
  await grantRole(deployed.instances, OPERATOR_ROLE, deployer, "instances.OPERATOR_ROLE -> deployer");

  console.log("\nAll roles granted.\n");

  // =========================================================================
  // Summary
  // =========================================================================

  const remainingBalance = await publicClient.getBalance({ address: deployer });
  const gasUsed = balance - remainingBalance;

  console.log("=== DEPLOYMENT SUMMARY ===\n");
  console.log("Network:    MegaETH Testnet (Carrot)");
  console.log("Chain ID:  ", chainId);
  console.log("RPC URL:    https://carrot.megaeth.com/rpc");
  console.log("Deployer:  ", deployer);
  console.log("Treasury:  ", TREASURY_ADDRESS);

  console.log("\nProxy Addresses (use these for interactions):");
  console.log(`  MockIXToken:          ${deployed.token}`);
  console.log(`  ContractTemplates:    ${deployed.templates}`);
  console.log(`  ContractInstances:    ${deployed.instances}`);
  console.log(`  ContractParties:      ${deployed.parties}`);
  console.log(`  ContractResults:      ${deployed.results}`);
  console.log(`  ContractConsents:     ${deployed.consents}`);
  console.log(`  ContractSettlements:  ${deployed.settlements}`);

  console.log("\nImplementation Addresses (do not interact directly):");
  console.log(`  MockIXToken:          ${deployed.tokenImpl}`);
  console.log(`  ContractTemplates:    ${deployed.templatesImpl}`);
  console.log(`  ContractInstances:    ${deployed.instancesImpl}`);
  console.log(`  ContractParties:      ${deployed.partiesImpl}`);
  console.log(`  ContractResults:      ${deployed.resultsImpl}`);
  console.log(`  ContractConsents:     ${deployed.consentsImpl}`);
  console.log(`  ContractSettlements:  ${deployed.settlementsImpl}`);

  console.log("\nRole Assignments:");
  console.log("  CONTRACT_ROLE on Instances -> Results, Consents, Settlements");
  console.log("  CONTRACT_ROLE on Parties   -> Settlements");
  console.log("  SYSTEM_ROLE on Instances   -> deployer");
  console.log("  OPERATOR_ROLE on Instances -> deployer");

  console.log("\nTransaction Hashes:");
  for (const [key, hash] of Object.entries(txHashes)) {
    console.log(`  ${key}: ${hash}`);
  }

  console.log(`\nTotal deployment cost: ${(Number(gasUsed) / 1e18).toFixed(6)} ETH`);
  console.log(`Remaining balance:    ${(Number(remainingBalance) / 1e18).toFixed(6)} ETH`);
  console.log("\n=== DEPLOYMENT COMPLETE ===");
}

main().catch((error) => {
  console.error("Deployment failed:", error);
  process.exit(1);
});
