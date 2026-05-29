// Faz 5 live example: gasless, relayer-submitted ZK-gated payment.
//
// The operator signs an EIP-712 PaymentAuthorization (the EVM form of an x402
// payment header) off-chain and pays NO gas. A separate relayer submits the
// authorization plus a real Groth16 proof and pays the gas. We assert the
// operator's native MOCA balance is unchanged by the release.
//
//   npm run pay-gasless
//
// Env: MOCA_DEPLOYER_PRIVATE_KEY (operator), MOCA_RELAYER_PRIVATE_KEY (relayer),
//      MOCA_POLICY_REGISTRY, MOCA_COMPLIANCE_ESCROW, MOCA_TEST_TOKEN.

import { resolve } from "node:path";
import { config as loadEnv } from "dotenv";
import { parseUnits, type Address, type Hex } from "viem";
import { ApertureMocaClient } from "../src/index.js";
import { generatePaymentProof } from "../src/proof.js";
import { erc20Abi } from "../src/abis.js";

loadEnv({ path: resolve(process.cwd(), "..", ".env") });

function env(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`missing env ${name}`);
  return v;
}
const key = (n: string): Hex => {
  const v = env(n);
  return (v.startsWith("0x") ? v : `0x${v}`) as Hex;
};

async function main() {
  const addresses = {
    policyRegistry: env("MOCA_POLICY_REGISTRY") as Address,
    complianceEscrow: env("MOCA_COMPLIANCE_ESCROW") as Address,
  };
  const token = env("MOCA_TEST_TOKEN") as Address;
  const recipient = "0x000000000000000000000000000000000000bEEF" as Address;
  const policyId = "0x000000000000000000000000000000000000000000000000000000000000a9e5" as Hex;
  const amount = parseUnits("1", 6);

  const operator = new ApertureMocaClient({ rpcUrl: process.env.MOCA_RPC_URL, privateKey: key("MOCA_DEPLOYER_PRIVATE_KEY"), addresses });
  const relayer = new ApertureMocaClient({ rpcUrl: process.env.MOCA_RPC_URL, privateKey: key("MOCA_RELAYER_PRIVATE_KEY"), addresses });
  const operatorAddr = operator.account!.address;
  const relayerAddr = relayer.account!.address;
  console.log("operator:", operatorAddr, "\nrelayer :", relayerAddr);

  // One-time setup: ensure the operator has funds locked in this escrow.
  const locked = await operator.lockedBalanceOf(operatorAddr, token);
  if (locked < amount) {
    const need = amount * 20n;
    console.log("operator funding escrow (one-time)...");
    const mintTx = await operator.walletClient!.writeContract({
      address: token, abi: erc20Abi, functionName: "mint", args: [operatorAddr, need], account: operator.account!, chain: operator.publicClient.chain,
    });
    await operator.publicClient.waitForTransactionReceipt({ hash: mintTx });
    await operator.publicClient.waitForTransactionReceipt({ hash: await operator.approve(token, need) });
    await operator.publicClient.waitForTransactionReceipt({ hash: await operator.deposit(token, need) });
  }

  // Build a real proof bound to (recipient, token, amount) for this operator.
  const timestamp = (await operator.publicClient.getBlock({ blockTag: "latest" })).timestamp;
  const dailyBefore = await operator.effectiveDailySpent(operatorAddr);
  const proof = await generatePaymentProof({ recipient, token, amount, timestamp, dailyBefore });

  const nonce = await operator.nonceOf(operatorAddr);
  const auth = { operator: operatorAddr, policyId, token, recipient, amount, nonce, deadline: timestamp + 3600n };

  // Operator signs off-chain (no gas, no transaction).
  const signature = await operator.signPaymentAuthorization(auth);
  console.log("operator signed authorization (off-chain, gasless). nonce:", nonce.toString());

  const opNativeBefore = await operator.publicClient.getBalance({ address: operatorAddr });
  const recipBefore = await operator.publicClient.readContract({ address: token, abi: erc20Abi, functionName: "balanceOf", args: [recipient] });

  // Relayer submits and pays the gas.
  const txHash = await relayer.submitSignedRelease(proof, auth, signature);
  console.log("relayer submitted releaseWithProofSigned:", txHash);
  await relayer.publicClient.waitForTransactionReceipt({ hash: txHash });

  const opNativeAfter = await operator.publicClient.getBalance({ address: operatorAddr });
  const recipAfter = await operator.publicClient.readContract({ address: token, abi: erc20Abi, functionName: "balanceOf", args: [recipient] });

  console.log("recipient atUSD:", recipBefore.toString(), "->", recipAfter.toString());
  console.log("operator MOCA  :", opNativeBefore.toString(), "->", opNativeAfter.toString());
  console.log(opNativeBefore === opNativeAfter ? ">>> GASLESS confirmed: operator native balance unchanged by the payment" : ">>> NOTE: operator native balance changed");
  console.log("Explorer:", `https://testnet-scan.mocachain.org/tx/${txHash}`);
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
