import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { config as loadEnv } from "dotenv";

const __dirname = dirname(fileURLToPath(import.meta.url));
// Repo-root .env (three levels up: src -> credential-service -> moca -> root)
export const REPO_ROOT = resolve(__dirname, "..", "..");
loadEnv({ path: resolve(REPO_ROOT, ".env") });

export function env(name, required = true) {
  const v = process.env[name];
  if (required && !v) throw new Error(`missing env ${name} (set it in ${REPO_ROOT}/.env)`);
  return v;
}

export const config = {
  partnerId: () => env("MOCA_PARTNER_ID"),
  issuerDid: () => env("MOCA_ISSUER_DID"),
  issuanceProgramId: () => env("MOCA_ISSUANCE_PROGRAM_ID"),
  schemaType: () => env("MOCA_SCHEMA_TYPE"),
  sandboxApi: () => env("MOCA_SANDBOX_API").replace(/\/+$/, ""),
  jwksPrivateKey: () => env("MOCA_JWKS_PRIVATE_KEY"),
  jwksKid: () => env("MOCA_JWKS_KID"),
  jwksPublicUrl: () => env("MOCA_JWKS_PUBLIC_URL", false),
  rpcUrl: () => env("MOCA_RPC_URL", false) || "https://rpc.testnet.mocachain.dev",
  complianceEscrow: () => env("MOCA_COMPLIANCE_ESCROW", false),
};
