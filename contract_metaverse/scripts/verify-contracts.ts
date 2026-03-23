/**
 * IX Metaverse Contract System — Verify All Contracts on MegaETH Testnet
 *
 * Verifies implementation contracts source code on MegaETH block explorer.
 * Uses MEGAETH_API_KEY from .env.
 *
 * Usage:
 *   npx hardhat run scripts/verify-contracts.ts --network megaethTestnet
 */

import { network } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { execSync } from "child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Implementation contracts to verify (these are the actual code, not proxies)
const IMPLEMENTATIONS = [
  { name: "MockIXToken", path: "contracts/mocks/MockIXToken.sol:MockIXToken", address: "0xf2aa8a13fe8c4d8585d69d606ba08927a08044ba" },
  { name: "ContractTemplates", path: "contracts/ContractTemplates.sol:ContractTemplates", address: "0xf96147e8aada6541fdc142e7bc77157e92b2b9b1" },
  { name: "ContractInstances", path: "contracts/ContractInstances.sol:ContractInstances", address: "0x05d202df16330437f68856e0c5ac49259cf9cfcd" },
  { name: "ContractParties", path: "contracts/ContractParties.sol:ContractParties", address: "0x74d0653289cc66092d123690051d982f02e0d281" },
  { name: "ContractResults", path: "contracts/ContractResults.sol:ContractResults", address: "0xcb48b719fe0b5580af762d813368748999671d4a" },
  { name: "ContractConsents", path: "contracts/ContractConsents.sol:ContractConsents", address: "0x8f4000b0d02f65a6612c2bd63c0b60c689b4554c" },
  { name: "ContractSettlements", path: "contracts/ContractSettlements.sol:ContractSettlements", address: "0xe4f1983fa766a59ba31605100cca556cd482e903" },
];

async function main() {
  console.log("═══════════════════════════════════════════════");
  console.log("  IX Metaverse — Contract Source Verification");
  console.log("═══════════════════════════════════════════════\n");

  const apiKey = process.env.MEGAETH_API_KEY;
  if (!apiKey) {
    console.error("❌ MEGAETH_API_KEY not found in .env");
    process.exit(1);
  }
  console.log("API Key:", apiKey.slice(0, 6) + "..." + apiKey.slice(-4));
  console.log("Network: megaethTestnet");
  console.log("");

  const results: { name: string; address: string; status: string }[] = [];

  for (const impl of IMPLEMENTATIONS) {
    console.log(`🔍 Verifying ${impl.name} at ${impl.address}...`);

    try {
      const cmd = `npx hardhat verify --network megaethTestnet --contract "${impl.path}" ${impl.address} 2>&1`;
      const output = execSync(cmd, {
        cwd: path.join(__dirname, ".."),
        timeout: 120000,
        encoding: "utf-8",
      });

      if (output.includes("Already Verified") || output.includes("already verified")) {
        console.log(`   ✅ ${impl.name} — already verified`);
        results.push({ name: impl.name, address: impl.address, status: "ALREADY VERIFIED" });
      } else if (output.includes("Successfully verified") || output.includes("successfully verified")) {
        console.log(`   ✅ ${impl.name} — verified!`);
        results.push({ name: impl.name, address: impl.address, status: "VERIFIED" });
      } else {
        console.log(`   ⚠️  ${impl.name} — output: ${output.slice(0, 200)}`);
        results.push({ name: impl.name, address: impl.address, status: "UNKNOWN: " + output.slice(0, 80) });
      }
    } catch (error: any) {
      const errMsg = error.stdout || error.stderr || error.message || "";
      if (errMsg.includes("Already Verified") || errMsg.includes("already verified")) {
        console.log(`   ✅ ${impl.name} — already verified`);
        results.push({ name: impl.name, address: impl.address, status: "ALREADY VERIFIED" });
      } else {
        console.log(`   ❌ ${impl.name} — failed: ${errMsg.slice(0, 200)}`);
        results.push({ name: impl.name, address: impl.address, status: "FAILED: " + errMsg.slice(0, 80) });
      }
    }

    // Small delay between verifications to avoid rate limiting
    await new Promise(r => setTimeout(r, 2000));
  }

  // Summary
  console.log("\n═══════════════════════════════════════════════");
  console.log("  Verification Summary");
  console.log("═══════════════════════════════════════════════\n");

  for (const r of results) {
    const icon = r.status.includes("VERIFIED") ? "✅" : "❌";
    console.log(`  ${icon} ${r.name.padEnd(25)} ${r.address.slice(0, 10)}... ${r.status}`);
  }

  const verified = results.filter(r => r.status.includes("VERIFIED")).length;
  console.log(`\n  Result: ${verified}/${results.length} contracts verified`);

  // Save report
  const reportDir = path.join(__dirname, "../deployments");
  if (!fs.existsSync(reportDir)) fs.mkdirSync(reportDir, { recursive: true });
  const reportPath = path.join(reportDir, "verification-report.json");
  fs.writeFileSync(reportPath, JSON.stringify({ timestamp: new Date().toISOString(), results }, null, 2));
  console.log(`  Report: ${reportPath}`);
}

main().catch((error) => {
  console.error("\n❌ Verification failed:", error.message);
  process.exitCode = 1;
});
