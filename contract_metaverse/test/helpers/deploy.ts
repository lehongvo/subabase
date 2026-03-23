/**
 * Deploy helper for IX Metaverse Contract System integration tests.
 * Deploys all 6 contracts + MockIXToken, initializes, grants roles,
 * and sets cross-references.
 */
import { network } from "hardhat";
import {
  encodeFunctionData,
  encodeAbiParameters,
  parseAbiParameters,
  parseEther,
  keccak256,
  toHex,
  getAddress,
  type Address,
} from "viem";

// --------------------------------------------------------------------------
// Role constants (must match keccak256 in Solidity)
// --------------------------------------------------------------------------
export const ADMIN_ROLE = keccak256(toHex("ADMIN_ROLE"));
export const SYSTEM_ROLE = keccak256(toHex("SYSTEM_ROLE"));
export const OPERATOR_ROLE = keccak256(toHex("OPERATOR_ROLE"));
export const CONTRACT_ROLE = keccak256(toHex("CONTRACT_ROLE"));
export const SERVER_ROLE = keccak256(toHex("SERVER_ROLE"));
export const SETTLER_ROLE = keccak256(toHex("SETTLER_ROLE"));
export const DEFAULT_ADMIN_ROLE =
  "0x0000000000000000000000000000000000000000000000000000000000000000" as `0x${string}`;

// --------------------------------------------------------------------------
// Helpers to ABI-encode template conditions and reward rules
// --------------------------------------------------------------------------
export function encodeConditions(
  minBet: bigint,
  maxBet: bigint,
  rounds: bigint,
  timeoutSeconds: bigint
): `0x${string}` {
  return encodeAbiParameters(
    parseAbiParameters("uint256, uint256, uint256, uint256"),
    [minBet, maxBet, rounds, timeoutSeconds]
  );
}

export function encodeRewardRules(
  drawRefund: boolean,
  winnerPct: bigint
): `0x${string}` {
  return encodeAbiParameters(
    parseAbiParameters("bool, uint256"),
    [drawRefund, winnerPct]
  );
}

export function encodeResultData(
  winnerId: Address,
  winnerMove: string,
  loserMove: string,
  roundsPlayed: bigint,
  score: string,
  isDraw: boolean
): `0x${string}` {
  return encodeAbiParameters(
    parseAbiParameters("address, string, string, uint256, string, bool"),
    [winnerId, winnerMove, loserMove, roundsPlayed, score, isDraw]
  );
}

export const CHALLENGER_ROLE = keccak256(toHex("challenger"));
export const OPPONENT_ROLE = keccak256(toHex("opponent"));

// --------------------------------------------------------------------------
// OZ v5 Initializable storage slot — must be reset before calling initialize()
// on implementation contracts (constructor calls _disableInitializers()).
// Slot = keccak256("openzeppelin.storage.Initializable") - 1
// --------------------------------------------------------------------------
const OZ_INITIALIZABLE_SLOT =
  "0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00" as `0x${string}`;

/**
 * Reset the OZ v5 Initializable storage slot to allow calling initialize()
 * on an implementation contract that has _disableInitializers() in its constructor.
 */
async function resetInitialized(
  testClient: any,
  contractAddress: Address
) {
  await testClient.setStorageAt({
    address: contractAddress,
    index: OZ_INITIALIZABLE_SLOT,
    value: "0x0000000000000000000000000000000000000000000000000000000000000000" as `0x${string}`,
  });
}

// --------------------------------------------------------------------------
// Main deploy function
// --------------------------------------------------------------------------
export async function deployFullSystem() {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const testClient = await viem.getTestClient();
  const [admin, systemAccount, playerA, playerB, treasury, outsider] =
    await viem.getWalletClients();

  // ---- Deploy MockIXToken ----
  const token = await viem.deployContract("MockIXToken");

  // ---- Deploy ContractTemplates ----
  const templates = await viem.deployContract("ContractTemplates");
  await resetInitialized(testClient, templates.address);
  await templates.write.initialize([admin.account.address]);

  // ---- Deploy ContractInstances ----
  const instances = await viem.deployContract("ContractInstances");
  await resetInitialized(testClient, instances.address);
  await instances.write.initialize([
    admin.account.address,
    templates.address,
  ]);

  // ---- Deploy ContractParties ----
  const parties = await viem.deployContract("ContractParties");
  await resetInitialized(testClient, parties.address);
  await parties.write.initialize([
    admin.account.address,
    instances.address,
    token.address,
  ]);

  // ---- Deploy ContractResults ----
  const results = await viem.deployContract("ContractResults");
  await resetInitialized(testClient, results.address);
  await results.write.initialize([
    admin.account.address,
    instances.address,
  ]);

  // ---- Deploy ContractConsents ----
  const consents = await viem.deployContract("ContractConsents");
  await resetInitialized(testClient, consents.address);
  await consents.write.initialize([
    admin.account.address,
    instances.address,
    parties.address,
    templates.address,
  ]);

  // ---- Deploy ContractSettlements ----
  const settlements = await viem.deployContract("ContractSettlements");
  await resetInitialized(testClient, settlements.address);
  await settlements.write.initialize([
    admin.account.address,
    instances.address,
    parties.address,
    results.address,
    consents.address,
    treasury.account.address,
  ]);

  // ========================================================================
  // Grant roles
  // ========================================================================

  // ContractTemplates: admin already has ADMIN_ROLE from initialize

  // ContractInstances: grant SYSTEM_ROLE, CONTRACT_ROLE
  await instances.write.grantRole([SYSTEM_ROLE, admin.account.address]);
  await instances.write.grantRole([SYSTEM_ROLE, systemAccount.account.address]);
  await instances.write.grantRole([CONTRACT_ROLE, results.address]);
  await instances.write.grantRole([CONTRACT_ROLE, consents.address]);
  await instances.write.grantRole([CONTRACT_ROLE, settlements.address]);
  await instances.write.grantRole([OPERATOR_ROLE, admin.account.address]);

  // ContractParties: grant CONTRACT_ROLE for settlements to call releaseEscrow/refundEscrow
  await parties.write.grantRole([CONTRACT_ROLE, settlements.address]);
  await parties.write.grantRole([SYSTEM_ROLE, admin.account.address]);

  // ContractResults: grant SERVER_ROLE
  await results.write.grantRole([SERVER_ROLE, admin.account.address]);
  await results.write.grantRole([SERVER_ROLE, systemAccount.account.address]);

  // ContractConsents: grant SERVER_ROLE
  await consents.write.grantRole([SERVER_ROLE, admin.account.address]);
  await consents.write.grantRole([SERVER_ROLE, systemAccount.account.address]);

  // ContractSettlements: grant SETTLER_ROLE
  await settlements.write.grantRole([SETTLER_ROLE, admin.account.address]);
  await settlements.write.grantRole([SETTLER_ROLE, systemAccount.account.address]);

  // ========================================================================
  // Set cross-references
  // ========================================================================

  // ContractInstances needs: parties, results, consents, settlements
  await instances.write.setPartiesContract([parties.address]);
  await instances.write.setResultsContract([results.address]);
  await instances.write.setConsentsContract([consents.address]);
  await instances.write.setSettlementsContract([settlements.address]);

  // ContractParties needs: templates
  await parties.write.setTemplatesContract([templates.address]);

  // ContractSettlements needs: templates
  await settlements.write.setTemplatesContract([templates.address]);

  return {
    // Contracts
    token,
    templates,
    instances,
    parties,
    results,
    consents,
    settlements,
    // Accounts
    admin,
    systemAccount,
    playerA,
    playerB,
    treasury,
    outsider,
    // Clients
    publicClient,
  };
}

export type DeployedSystem = Awaited<ReturnType<typeof deployFullSystem>>;

// --------------------------------------------------------------------------
// Helper: create an RPS template and return its templateId
// --------------------------------------------------------------------------
export async function createRPSTemplate(
  sys: DeployedSystem,
  opts?: {
    feeRateBps?: number;
    minBet?: bigint;
    maxBet?: bigint;
    timeoutSeconds?: bigint;
    name?: string;
  }
) {
  const feeRateBps = opts?.feeRateBps ?? 300;
  const minBet = opts?.minBet ?? parseEther("10");
  const maxBet = opts?.maxBet ?? parseEther("100");
  const timeoutSeconds = opts?.timeoutSeconds ?? 15n;
  const name = opts?.name ?? "RPS Casual Lobby 1";

  const conditions = encodeConditions(minBet, maxBet, 1n, timeoutSeconds);
  const rewardRules = encodeRewardRules(true, 95n);

  const hash = await sys.templates.write.createTemplate([
    name,
    0, // ContractType.RPS
    conditions,
    rewardRules,
    1, // PaymentType.IXFreePoint
    feeRateBps,
    0, // ChainRecordPolicy.Required
    "0x0000000000000000000000000000000000000000000000000000000000000000" as `0x${string}`,
  ]);

  // Read the TemplateCreated event to get templateId
  const receipt = await sys.publicClient.waitForTransactionReceipt({ hash });
  const event = receipt.logs[0];
  // templateId is the first indexed topic (topics[1])
  const templateId = event.topics[1] as `0x${string}`;

  return templateId;
}

// --------------------------------------------------------------------------
// Helper: Mint tokens to players and approve parties contract
// --------------------------------------------------------------------------
export async function mintAndApprove(
  sys: DeployedSystem,
  amount: bigint = parseEther("100")
) {
  // Mint to playerA
  await sys.token.write.mint([sys.playerA.account.address, amount]);
  // Mint to playerB
  await sys.token.write.mint([sys.playerB.account.address, amount]);

  // Approve parties contract to spend on behalf of playerA
  await sys.playerA.writeContract({
    address: sys.token.address,
    abi: ERC20_APPROVE_ABI,
    functionName: "approve",
    args: [sys.parties.address, amount],
  });

  // Approve parties contract to spend on behalf of playerB
  await sys.playerB.writeContract({
    address: sys.token.address,
    abi: ERC20_APPROVE_ABI,
    functionName: "approve",
    args: [sys.parties.address, amount],
  });
}

// --------------------------------------------------------------------------
// ERC20 approve ABI fragment for direct wallet calls
// --------------------------------------------------------------------------
const ERC20_APPROVE_ABI = [
  {
    name: "approve",
    type: "function",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
    stateMutability: "nonpayable",
  },
] as const;

// --------------------------------------------------------------------------
// Helper: get contract instance as a specific user
// Uses impersonation via test client to ensure transactions from the
// correct sender are properly mined in Hardhat 3.
// --------------------------------------------------------------------------
export async function getContractAsUser<T extends string>(
  contractName: T,
  contractAddress: Address,
  userAddress: Address
) {
  const { viem } = await network.connect();
  const clients = await viem.getWalletClients();
  const wallet = clients.find(
    (c) => getAddress(c.account.address) === getAddress(userAddress)
  );
  if (!wallet) throw new Error(`No wallet client for ${userAddress}`);
  return viem.getContractAt(contractName, contractAddress, {
    client: { wallet },
  });
}

/**
 * Get a wallet client for a given address from the deployed system.
 */
export function getWalletClient(sys: DeployedSystem, address: Address) {
  const all = [
    sys.admin,
    sys.systemAccount,
    sys.playerA,
    sys.playerB,
    sys.treasury,
    sys.outsider,
  ];
  const client = all.find(
    (c) => getAddress(c.account.address) === getAddress(address)
  );
  if (!client) throw new Error(`No wallet client for ${address}`);
  return client;
}

// --------------------------------------------------------------------------
// Helper: Run full RPS lifecycle up to settlement
// --------------------------------------------------------------------------
export async function runFullRPSLifecycle(sys: DeployedSystem) {
  const betAmount = parseEther("50");

  // 1. Create template
  const templateId = await createRPSTemplate(sys);

  // 2. Mint tokens and approve
  await mintAndApprove(sys);

  // 3. Create instance
  const createHash = await sys.instances.write.createInstance([
    templateId,
    "0x" as `0x${string}`,
  ]);
  const createReceipt = await sys.publicClient.waitForTransactionReceipt({
    hash: createHash,
  });
  const instanceId = createReceipt.logs[0].topics[1] as `0x${string}`;

  // 4. Player A joins
  const partiesA = await getContractAsUser(
    "ContractParties",
    sys.parties.address,
    sys.playerA.account.address
  );
  await partiesA.write.joinContract([
    instanceId,
    CHALLENGER_ROLE,
    betAmount,
    1, // PointType.IXFreePoint
  ]);

  // 5. Player B joins
  const partiesB = await getContractAsUser(
    "ContractParties",
    sys.parties.address,
    sys.playerB.account.address
  );
  await partiesB.write.joinContract([
    instanceId,
    OPPONENT_ROLE,
    betAmount,
    1, // PointType.IXFreePoint
  ]);

  // 6. Activate instance
  await sys.instances.write.activateInstance([instanceId]);

  // 7. Report result: B wins
  const resultData = encodeResultData(
    sys.playerB.account.address,
    "rock",
    "scissors",
    1n,
    "1-0",
    false
  );
  await sys.results.write.reportResult([
    instanceId,
    resultData,
    0, // ResultSource.System
    true, // isFinal
  ]);

  // 8. Both consent
  await sys.consents.write.submitConsent([
    instanceId,
    sys.playerA.account.address,
    true,
    "0x" as `0x${string}`,
    "",
  ]);
  await sys.consents.write.submitConsent([
    instanceId,
    sys.playerB.account.address,
    true,
    "0x" as `0x${string}`,
    "",
  ]);

  // 9. Settle
  await sys.settlements.write.settleContract([instanceId]);

  return { templateId, instanceId, betAmount };
}
