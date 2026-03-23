/**
 * IX Metaverse Contract System — Verify All Contracts on MegaETH Testnet
 *
 * Reads deployed addresses from deployments/megaeth-testnet.json
 * and verifies source code using MEGAETH_API_KEY.
 *
 * Usage:
 *   npx hardhat run scripts/verify-contracts.ts
 */

import { network } from "hardhat";
import * as fs from "fs";
import * as path from "path";

// Contract names and their constructor args (implementation contracts have no constructor args)
const CONTRACTS_TO_VERIFY = [
  { name: "MockIXToken", constructorArgs: [] },
  { name: "ContractTemplates", constructorArgs: [] },
  { name: "ContractInstances", constructorArgs: [] },
  { name: "ContractParties", constructorArgs: [] },
  { name: "ContractResults", constructorArgs: [] },
  { name: "ContractConsents", constructorArgs: [] },
  { name: "ContractSettlements", constructorArgs: [] },
];

async function main() {
  console.log("═══════════════════════════════════════════════");
  console.log("  IX Metaverse — Contract Source Verification");
  console.log("═══════════════════════════════════════════════\n");

  // Load deployment addresses
  const deploymentsPath = path.join(__dirname, "../deployments/megaeth-testnet.json");
  if (!fs.existsSync(deploymentsPath)) {
    console.error("❌ No deployment file found at", deploymentsPath);
    console.error("   Run deploy-megaeth.ts first.");
    process.exit(1);
  }

  const deployment = JSON.parse(fs.readFileSync(deploymentsPath, "utf-8"));
  console.log("Network:", deployment.network);
  console.log("Chain ID:", deployment.chainId);
  console.log("Deployed at:", deployment.timestamp);
  console.log("");

  const apiKey = process.env.MEGAETH_API_KEY;
  if (!apiKey) {
    console.error("❌ MEGAETH_API_KEY not found in .env");
    process.exit(1);
  }
  console.log("API Key: ", apiKey.slice(0, 6) + "..." + apiKey.slice(-4));
  console.log("");

  // Verify each contract
  const results: { name: string; address: string; status: string }[] = [];

  for (const contract of CONTRACTS_TO_VERIFY) {
    const address = deployment.contracts?.[contract.name]
      || deployment.implementations?.[contract.name]
      || null;

    if (!address) {
      console.log(`⚠️  ${contract.name}: No address found in deployment file, skipping`);
      results.push({ name: contract.name, address: "N/A", status: "SKIPPED" });
      continue;
    }

    console.log(`🔍 Verifying ${contract.name} at ${address}...`);

    try {
      // Use hardhat verify task
      // Note: This requires @nomicfoundation/hardhat-verify plugin
      // and etherscan config in hardhat.config.ts
      await (globalThis as any).hre?.run("verify:verify", {
        address: address,
        constructorArguments: contract.constructorArgs,
        contract: `contracts/${contract.name}.sol:${contract.name}`,
      });
      console.log(`   ✅ ${contract.name} verified!`);
      results.push({ name: contract.name, address, status: "VERIFIED" });
    } catch (error: any) {
      if (error.message?.includes("Already Verified")) {
        console.log(`   ✅ ${contract.name} already verified`);
        results.push({ name: contract.name, address, status: "ALREADY VERIFIED" });
      } else {
        console.log(`   ❌ ${contract.name} verification failed: ${error.message?.slice(0, 100)}`);
        results.push({ name: contract.name, address, status: "FAILED: " + error.message?.slice(0, 50) });
      }
    }
  }

  // Also try to verify proxy contracts if they exist
  if (deployment.proxies) {
    console.log("\n--- Proxy Contracts ---\n");
    for (const [name, address] of Object.entries(deployment.proxies)) {
      console.log(`🔍 Verifying proxy ${name} at ${address}...`);
      try {
        await (globalThis as any).hre?.run("verify:verify", {
          address: address as string,
          constructorArguments: [], // Proxy constructor args would need impl + admin + data
        });
        console.log(`   ✅ Proxy ${name} verified!`);
        results.push({ name: `Proxy:${name}`, address: address as string, status: "VERIFIED" });
      } catch (error: any) {
        if (error.message?.includes("Already Verified")) {
          console.log(`   ✅ Proxy ${name} already verified`);
          results.push({ name: `Proxy:${name}`, address: address as string, status: "ALREADY VERIFIED" });
        } else {
          console.log(`   ❌ Proxy ${name} failed: ${error.message?.slice(0, 100)}`);
          results.push({ name: `Proxy:${name}`, address: address as string, status: "FAILED" });
        }
      }
    }
  }

  // Summary
  console.log("\n═══════════════════════════════════════════════");
  console.log("  Verification Summary");
  console.log("═══════════════════════════════════════════════\n");

  for (const r of results) {
    const icon = r.status.startsWith("VERIFIED") || r.status.startsWith("ALREADY")
      ? "✅" : r.status === "SKIPPED" ? "⚠️" : "❌";
    console.log(`  ${icon} ${r.name.padEnd(25)} ${r.address.slice(0, 10)}... ${r.status}`);
  }

  const verified = results.filter(r => r.status.includes("VERIFIED")).length;
  const total = results.filter(r => r.status !== "SKIPPED").length;
  console.log(`\n  Result: ${verified}/${total} contracts verified`);

  // Save verification report
  const reportPath = path.join(__dirname, "../deployments/verification-report.json");
  fs.writeFileSync(reportPath, JSON.stringify({ timestamp: new Date().toISOString(), results }, null, 2));
  console.log(`\n  Report saved to: ${reportPath}`);
}

main().catch((error) => {
  console.error("\n❌ Verification failed:", error);
  process.exitCode = 1;
});
