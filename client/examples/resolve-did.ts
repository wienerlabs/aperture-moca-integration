// Faz 3 live example: resolve an agent DID over the Moca testnet RPC and map it
// to its EVM smart-account, then reverse-resolve. Read-only (no key needed).
//
//   npm run resolve
//
// Reads MOCA_AGENT_REGISTRY (+ optional MOCA_RPC_URL) from the repo-root .env.

import { resolve } from "node:path";
import { config as loadEnv } from "dotenv";
import type { Address } from "viem";
import { ApertureMocaClient } from "../src/index.js";

loadEnv({ path: resolve(process.cwd(), "..", ".env") });

function env(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`missing env ${name}`);
  return v;
}

async function main() {
  const did = process.argv[2] ?? "did:moca:aperture-agent-1";

  const client = new ApertureMocaClient({
    rpcUrl: process.env.MOCA_RPC_URL,
    addresses: {
      // policyRegistry / complianceEscrow not used by the resolver; pass them
      // for a complete config when available.
      policyRegistry: (process.env.MOCA_POLICY_REGISTRY ?? "0x0000000000000000000000000000000000000000") as Address,
      complianceEscrow: (process.env.MOCA_COMPLIANCE_ESCROW ?? "0x0000000000000000000000000000000000000000") as Address,
      agentRegistry: env("MOCA_AGENT_REGISTRY") as Address,
    },
  });

  console.log("resolving DID over Moca RPC:", did);
  const agent = await client.resolveAgent(did);
  console.log("  smartAccount:", agent.smartAccount);
  console.log("  authority   :", agent.authority);
  console.log("  agentId     :", agent.agentId);
  console.log("  endpoint    :", agent.endpoint);
  console.log("  metadataURI :", agent.metadataURI);

  const reverse = await client.didOf(agent.smartAccount);
  console.log("reverse didOf(", agent.smartAccount, ") =>", reverse);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
