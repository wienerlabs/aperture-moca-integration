// Generate an RS256 keypair for AIR Kit Partner JWT signing and write the
// private JWK (base64 JSON) + kid into the repo-root .env. Prints only the
// public material and the kid; the private key never reaches stdout.
//
//   npm run gen-keys
//
// After running, register the JWKS URL in the dashboard:
//   Account -> General Settings -> JWKS URL  =  <public-host>/.well-known/jwks.json

import { generateKeyPair, exportJWK } from "jose";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { REPO_ROOT } from "../src/config.mjs";

function randomKid() {
  // 16 random bytes hex. crypto.getRandomValues is available in Node 20+.
  const buf = new Uint8Array(16);
  crypto.getRandomValues(buf);
  return "aperture-" + Buffer.from(buf).toString("hex");
}

function upsertEnv(contents, key, value) {
  const line = `${key}=${value}`;
  const re = new RegExp(`^${key}=.*$`, "m");
  if (re.test(contents)) return contents.replace(re, line);
  return contents.replace(/\n*$/, "\n") + line + "\n";
}

async function main() {
  const { publicKey, privateKey } = await generateKeyPair("RS256", { extractable: true });
  const kid = randomKid();

  const privJwk = await exportJWK(privateKey);
  privJwk.kid = kid;
  privJwk.alg = "RS256";
  privJwk.use = "sig";

  const pubJwk = await exportJWK(publicKey);
  pubJwk.kid = kid;
  pubJwk.alg = "RS256";
  pubJwk.use = "sig";

  const privB64 = Buffer.from(JSON.stringify(privJwk), "utf8").toString("base64");

  const envPath = resolve(REPO_ROOT, ".env");
  let contents = "";
  try {
    contents = readFileSync(envPath, "utf8");
  } catch {
    contents = "";
  }
  contents = upsertEnv(contents, "MOCA_JWKS_PRIVATE_KEY", privB64);
  contents = upsertEnv(contents, "MOCA_JWKS_KID", kid);
  writeFileSync(envPath, contents);

  console.log("RS256 keypair generated and written to", envPath);
  console.log("  MOCA_JWKS_KID =", kid);
  console.log("\nPublic JWK (this is what /.well-known/jwks.json serves):");
  console.log(JSON.stringify({ keys: [pubJwk] }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
