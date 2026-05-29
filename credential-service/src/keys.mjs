import { importJWK, exportJWK } from "jose";
import { config } from "./config.mjs";

/// Decode the private JWK stored (base64 JSON) in MOCA_JWKS_PRIVATE_KEY.
function privateJwk() {
  const raw = config.jwksPrivateKey();
  let jwk;
  try {
    jwk = JSON.parse(Buffer.from(raw, "base64").toString("utf8"));
  } catch (e) {
    throw new Error("MOCA_JWKS_PRIVATE_KEY is not valid base64 JSON; run `npm run gen-keys`");
  }
  if (!jwk.kid) jwk.kid = config.jwksKid();
  if (!jwk.alg) jwk.alg = "RS256";
  return jwk;
}

/// The signing key (jose KeyLike) plus its kid.
export async function getSigningKey() {
  const jwk = privateJwk();
  const key = await importJWK(jwk, "RS256");
  return { key, kid: jwk.kid };
}

/// The public JWK set served at /.well-known/jwks.json. Derived from the
/// private JWK by exporting only the public components.
export async function getPublicJwks() {
  const jwk = privateJwk();
  const key = await importJWK(jwk, "RS256");
  const pub = await exportJWK(key);
  // exportJWK on an imported private key returns the full JWK; strip private
  // members so only the public key is published.
  for (const priv of ["d", "p", "q", "dp", "dq", "qi"]) delete pub[priv];
  pub.kid = jwk.kid;
  pub.alg = "RS256";
  pub.use = "sig";
  return { keys: [pub] };
}
