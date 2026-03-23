# IX Metaverse Contract System - MegaETH Testnet Deployment Report

| Item | Details |
| --- | --- |
| Document ID | IX-DEPLOY-001 |
| Date | 2026-03-23 |
| Network | MegaETH Testnet (Carrot) |
| Chain ID | 6343 |
| RPC URL | https://carrot.megaeth.com/rpc |
| Deployer | 0x00000fc78106799b5b1dbd71f206d8f0218b28fe |
| Treasury | 0x0000000000000000000000000000000000000001 |
| Total Cost | 0.000618 ETH |
| Status | SUCCESS |

---

## 1. Network Details

- **Network Name**: MegaETH Testnet (Carrot)
- **Chain ID**: 6343
- **RPC URL**: `https://carrot.megaeth.com/rpc`
- **Deployer Balance Before**: 0.999289 ETH
- **Deployer Balance After**: 0.998671 ETH
- **Total Deployment Cost**: 0.000618 ETH

---

## 2. Deployed Contracts

All core contracts are deployed behind `IXProxy` (wrapping OpenZeppelin `TransparentUpgradeableProxy`). Each proxy has its own `ProxyAdmin` instance owned by the deployer for future upgrades.

### Proxy Addresses (use these for all interactions)

| Contract | Proxy Address |
| --- | --- |
| MockIXToken | `0xf2aa8a13fe8c4d8585d69d606ba08927a08044ba` |
| ContractTemplates | `0x97bdfed7cf222cdca32d7e6c751b6879a762c474` |
| ContractInstances | `0x00b3ac1b04ff6712f7476bdb58c4f8c6895d853c` |
| ContractParties | `0x4950b69979942c235e5b576826eedb77eaf6ff00` |
| ContractResults | `0x1d13c2a5175651a51da741a9f5ebea1710b38bf5` |
| ContractConsents | `0x6cac3a10870750ffd6ced2e882c5a5332cd7cf74` |
| ContractSettlements | `0x8960ba72c560604688663e2c904fea3d3b2a68ff` |

### Implementation Addresses (do not interact directly)

| Contract | Implementation Address |
| --- | --- |
| MockIXToken | `0xf2aa8a13fe8c4d8585d69d606ba08927a08044ba` (direct, not proxied) |
| ContractTemplates | `0xf96147e8aada6541fdc142e7bc77157e92b2b9b1` |
| ContractInstances | `0x05d202df16330437f68856e0c5ac49259cf9cfcd` |
| ContractParties | `0x74d0653289cc66092d123690051d982f02e0d281` |
| ContractResults | `0xcb48b719fe0b5580af762d813368748999671d4a` |
| ContractConsents | `0x8f4000b0d02f65a6612c2bd63c0b60c689b4554c` |
| ContractSettlements | `0xe4f1983fa766a59ba31605100cca556cd482e903` |

---

## 3. Initialization and Cross-Contract Wiring

All contracts were initialized atomically during proxy deployment (initialize data encoded in the proxy constructor's `_data` parameter).

### Cross-Contract References Set

| Contract | Setter | Target |
| --- | --- | --- |
| ContractInstances | setPartiesContract | ContractParties proxy |
| ContractInstances | setResultsContract | ContractResults proxy |
| ContractInstances | setConsentsContract | ContractConsents proxy |
| ContractInstances | setSettlementsContract | ContractSettlements proxy |
| ContractParties | setTemplatesContract | ContractTemplates proxy |
| ContractSettlements | setTemplatesContract | ContractTemplates proxy |

---

## 4. Role Assignments

### CONTRACT_ROLE (inter-contract calls)

| Target Contract | Role Granted To | Purpose |
| --- | --- | --- |
| ContractInstances | ContractResults | `completeInstance()` |
| ContractInstances | ContractConsents | `disputeInstance()` |
| ContractInstances | ContractSettlements | `settleInstance()` |
| ContractParties | ContractSettlements | `releaseEscrow()`, `refundEscrow()` |

### Admin Roles (deployer)

| Target Contract | Role | Grantee |
| --- | --- | --- |
| ContractInstances | SYSTEM_ROLE | deployer |
| ContractInstances | OPERATOR_ROLE | deployer |
| All contracts | DEFAULT_ADMIN_ROLE | deployer (via initialize) |
| All contracts | ADMIN_ROLE | deployer (via initialize) |

---

## 5. Transaction Hashes

### Cross-Contract Reference Transactions

| Operation | Transaction Hash |
| --- | --- |
| instances.setPartiesContract | `0xcb450752baecbad89247d976166c2c4e3c701a56e7ce2f375f2f8e8cc709292e` |
| instances.setResultsContract | `0x3ef3307637414ec5fd2bb9e15ae707021ff80dbaf59bec9cac7718adbeeea3e8` |
| instances.setConsentsContract | `0xa1d92e9b1ea1981678962a3450e65165fd3b0fa327286694fb7901db1a591868` |
| instances.setSettlementsContract | `0xe63aa656288dddbe47e92ddd6cc83a6645d0dcf2646770825d23826281d4eef6` |
| parties.setTemplatesContract | `0x5b3c97a6de8a0caaf9c9c76f55c733dba1d102bc28ec95f89e507bf545f61481` |
| settlements.setTemplatesContract | `0x563d5e284e090e981c529a4e2a63e2952a732f35655372f7d6c9e4275fda0b43` |

### Role Grant Transactions

| Operation | Transaction Hash |
| --- | --- |
| instances.CONTRACT_ROLE -> Results | `0xd0f0e1c619f98c7b9f919808bc4f2f597109468a16b6f87b3cea9c80437a9cb7` |
| instances.CONTRACT_ROLE -> Consents | `0xd39c9415af790e796eb5743c45e2cf29547a8b9884a825c72e3a857ed127623b` |
| instances.CONTRACT_ROLE -> Settlements | `0x52675f79767c9b963a50a06b16a3938f42a2382e770302c0a9c77e49188ebeba` |
| parties.CONTRACT_ROLE -> Settlements | `0x16ac919d357a973762d3a621af4ab98c25fe0b06033a35e5bed5b0cde5a913d1` |
| instances.SYSTEM_ROLE -> deployer | `0x2c55d52d7f86f8c1d096e218e943548636f94265898b8d57609c39f005437af5` |
| instances.OPERATOR_ROLE -> deployer | `0xe3305e8905c6cf7ed24dc46ca58689c12c2b2a01a12c095e349319f0c81f235e` |

---

## 6. Gas Costs

| Phase | Estimated Cost |
| --- | --- |
| Contract Deployments (7 impls + 6 proxies) | ~0.000500 ETH |
| Cross-contract references (6 txs) | ~0.000060 ETH |
| Role grants (6 txs) | ~0.000058 ETH |
| **Total** | **0.000618 ETH** |

---

## 7. Errors Encountered

### Initial Attempt: Direct Deployment (No Proxy)

The first deployment attempt deployed contracts directly (without proxies). When calling `initialize()`, the transactions reverted with `InvalidInitialization` because all core contracts use `_disableInitializers()` in their constructors, locking the implementation against direct initialization.

**Resolution**: Switched to proxy-based deployment using `IXProxy` (a thin wrapper around `TransparentUpgradeableProxy`). The `initialize()` calldata is encoded into the proxy constructor's `_data` parameter, so initialization happens atomically during proxy deployment.

### Hardhat 3 Artifact Resolution

Hardhat 3 does not generate artifacts for contracts imported but not declared in source files. Creating `contracts/proxy/ProxyImports.sol` with only import statements was insufficient.

**Resolution**: Created `contracts/proxy/IXProxy.sol` -- a contract that inherits from `TransparentUpgradeableProxy`, causing Hardhat to generate the `IXProxy` artifact.

### Node.js Version Warning

Hardhat warns about Node.js 23.11.0 not being officially supported. Recommend using Node.js 22.x LTS.

---

## 8. Deployment Architecture

```
Deployer EOA
    |
    +-- MockIXToken (direct, no proxy)
    |
    +-- IXProxy (Templates) --> ProxyAdmin --> ContractTemplates impl
    +-- IXProxy (Instances) --> ProxyAdmin --> ContractInstances impl
    +-- IXProxy (Parties)   --> ProxyAdmin --> ContractParties impl
    +-- IXProxy (Results)   --> ProxyAdmin --> ContractResults impl
    +-- IXProxy (Consents)  --> ProxyAdmin --> ContractConsents impl
    +-- IXProxy (Settlements) --> ProxyAdmin --> ContractSettlements impl
```

Each proxy creates its own `ProxyAdmin` instance with the deployer as owner. To upgrade a contract, call `upgradeToAndCall()` on the `ProxyAdmin`.

---

## 9. How to Interact with Deployed Contracts

### Using Hardhat Console

```bash
npx hardhat console --network megaethTestnet
```

```typescript
const templates = await viem.getContractAt(
  "ContractTemplates",
  "0x97bdfed7cf222cdca32d7e6c751b6879a762c474"
);

// Create a template (requires ADMIN_ROLE)
await templates.write.createTemplate([
  "Rock Paper Scissors",  // name
  2,                       // contractType (RPS)
  100,                     // minBet (wei)
  1000000,                 // maxBet (wei)
  300,                     // feeRateBps (3%)
  3600,                    // consentTimeout (seconds)
  0,                       // chainRecordPolicy (None)
]);
```

### Using curl (REST API via Supabase)

Not applicable - these are on-chain contracts. Use viem, ethers.js, or any EVM-compatible client.

### Using viem directly

```typescript
import { createPublicClient, createWalletClient, http } from "viem";

const client = createPublicClient({
  transport: http("https://carrot.megaeth.com/rpc"),
});

// Read contract state
const result = await client.readContract({
  address: "0x97bdfed7cf222cdca32d7e6c751b6879a762c474",
  abi: ContractTemplatesABI,
  functionName: "getTemplate",
  args: [templateId],
});
```

---

## 10. Re-deployment Instructions

If you need to redeploy:

1. Ensure `.env` contains `PRIVATE_KEY` and `MEGAETH_TEST_NET_RPC`
2. Fund the deployer address with testnet ETH
3. Run:

```bash
npx hardhat run scripts/deploy-megaeth.ts
```

The script will deploy fresh contracts (it does not reuse previous deployments).

---

## 11. Next Steps

- [ ] Grant `SERVER_ROLE` to the metaverse game server address on ContractResults and ContractConsents
- [ ] Grant `SETTLER_ROLE` to the settlement automation address on ContractSettlements
- [ ] Create initial contract templates via `ContractTemplates.createTemplate()`
- [ ] Configure treasury to a proper multisig (current: `0x...0001` placeholder)
- [ ] Set up monitoring for contract events
- [ ] Verify contracts on block explorer (if MegaETH has one)
- [ ] Transfer `ProxyAdmin` ownership to a multisig for upgrade governance
