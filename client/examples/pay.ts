// End-to-end live example: lock funds and run a ZK-gated release through the
// deployed Aperture-on-Moca contracts using the viem client and a real proof.
//
// Reads config from the repo-root .env. Run from moca/client:
//   npm run pay
//
// Required env: MOCA_DEPLOYER_PRIVATE_KEY, MOCA_POLICY_REGISTRY,
// MOCA_COMPLIANCE_ESCROW, MOCA_TEST_TOKEN (+ optional MOCA_RPC_URL).

import { resolve } from "node:path";
import { config as loadEnv } from "dotenv";
import {
  createWalletClient,
  http,
  parseUnits,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

import { ApertureMocaClient } from "../src/index.js";
import { erc20Abi } from "../src/abis.js";
import { mocaTestnet } from "../src/chain.js";

loadEnv({ path: resolve(process.cwd(), "..", ".env") });

function env(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`missing env ${name}`);
  return v;
}

function normalizeKey(raw: string): Hex {
  return (raw.startsWith("0x") ? raw : `0x${raw}`) as Hex;
}

async function main() {
  const privateKey = normalizeKey(env("MOCA_DEPLOYER_PRIVATE_KEY"));
  const token = env("MOCA_TEST_TOKEN") as Address;
  const recipient = "0x000000000000000000000000000000000000bEEF" as Address;
  const policyId = "0x000000000000000000000000000000000000000000000000000000000000a9e5" as Hex;
  const amount = parseUnits("5", 6); // 5 atUSD (6 decimals)

  const client = new ApertureMocaClient({
    rpcUrl: process.env.MOCA_RPC_URL,
    privateKey,
    addresses: {
      policyRegistry: env("MOCA_POLICY_REGISTRY") as Address,
      complianceEscrow: env("MOCA_COMPLIANCE_ESCROW") as Address,
    },
  });
  const operator = client.account!.address;
  console.log("operator       :", operator);

  // Ensure the operator and policy exist (idempotent across runs).
  if (!(await client.operatorExists(operator))) {
    console.log("initializeOperator:", await client.initializeOperator("Aperture Moca Client Demo"));
  }
  try {
    await client.getActivePolicyCommitments(operator, policyId);
  } catch {
    // Policy not registered yet: probe its hash from a proof, then register it.
    const { generatePaymentProof } = await import("../src/proof.js");
    const probe = await generatePaymentProof({ recipient, token, amount, timestamp: 1735689600n });
    const merkleRoot = ("0x" + "12".padStart(64, "0")) as Hex;
    console.log("registerPolicy   :", await client.registerPolicy(operator, policyId, merkleRoot, probe.policyDataHash));
  }

  // Make sure escrow has at least `amount` locked; mint+approve+deposit if not.
  let locked = await client.lockedBalanceOf(operator, token);
  if (locked < amount) {
    const wallet = createWalletClient({
      account: privateKeyToAccount(privateKey),
      chain: mocaTestnet,
      transport: http(process.env.MOCA_RPC_URL),
    });
    const mintTx = await wallet.writeContract({
      address: token, abi: erc20Abi, functionName: "mint", args: [operator, amount * 10n],
    });
    console.log("mint             :", mintTx);
    console.log("approve          :", await client.approve(token, amount * 10n));
    console.log("deposit          :", await client.deposit(token, amount * 10n));
    locked = await client.lockedBalanceOf(operator, token);
  }
  console.log("locked balance   :", locked.toString());

  const before = await client.publicClient.readContract({
    address: token, abi: erc20Abi, functionName: "balanceOf", args: [recipient],
  });
  console.log("recipient before :", before.toString());

  const { txHash, proofTimestamp } = await client.payWithProof({ policyId, token, recipient, amount });
  console.log("payWithProof tx  :", txHash, "(proof ts", proofTimestamp.toString() + ")");
  await client.publicClient.waitForTransactionReceipt({ hash: txHash });

  const after = await client.publicClient.readContract({
    address: token, abi: erc20Abi, functionName: "balanceOf", args: [recipient],
  });
  console.log("recipient after  :", after.toString());
  console.log("daily spent      :", (await client.effectiveDailySpent(operator)).toString());
  console.log("\nExplorer:", `${mocaTestnet.blockExplorers.default.url}/tx/${txHash}`);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
