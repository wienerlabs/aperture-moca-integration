#!/usr/bin/env node
// Issue an "Aperture Verified Agent" credential on-behalf and poll its status.
//
//   node bin/issue-cli.mjs --email user@example.com --operator 0x... [--agent id] [--subject-id did:...]
//
// credentialSubject is built from real on-chain compliance data (the operator's
// ZK-gated release count in ComplianceEscrow).

import { buildCredentialSubject } from "../src/compliance.mjs";
import { issueOnBehalf, getStatus } from "../src/issue.mjs";

function arg(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i >= 0 ? process.argv[i + 1] : fallback;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const email = arg("--email");
  const operatorAddress = arg("--operator");
  if (!email || !operatorAddress) {
    throw new Error("usage: issue-cli.mjs --email <email> --operator <0xaddr> [--agent <id>] [--subject-id <did>]");
  }

  const credentialSubject = await buildCredentialSubject({
    operatorAddress,
    agentId: arg("--agent"),
    subjectId: arg("--subject-id"),
  });
  console.log("credentialSubject (from on-chain data):");
  console.log(JSON.stringify(credentialSubject, null, 2));

  console.log("\nissuing on-behalf...");
  const result = await issueOnBehalf({ email, credentialSubject });
  console.log("HTTP", result.status);
  console.log(JSON.stringify(result.body, null, 2));
  if (!result.ok) process.exit(1);

  const coreClaimHash = result.body.coreClaimHash ?? result.body.data?.coreClaimHash;
  if (!coreClaimHash) {
    console.log("\nno coreClaimHash in response; cannot poll status");
    return;
  }

  console.log(`\npolling status for coreClaimHash=${coreClaimHash} ...`);
  for (let i = 0; i < 10; i++) {
    await sleep(3000);
    const st = await getStatus({ coreClaimHash, email });
    console.log(`  [${i}] HTTP ${st.status}:`, JSON.stringify(st.body));
    const s = (st.body.status ?? st.body.data?.status ?? "").toString().toLowerCase();
    if (["issued", "completed", "success", "done", "revoked"].includes(s)) break;
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
