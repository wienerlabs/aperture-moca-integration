import { SignJWT } from "jose";
import { getSigningKey } from "./keys.mjs";
import { config } from "./config.mjs";

/// Sign a Partner JWT for the AIR Kit `x-partner-auth` header.
/// Claims per the docs: partnerId (always), scope, email (target AIR Account),
/// iat + exp (short-lived, 5 min). RS256 with a `kid` header that matches the
/// published JWKS.
export async function signPartnerJwt({ email, scope, partnerUserId, ttlSeconds = 300 }) {
  const { key, kid } = await getSigningKey();
  const partnerId = config.partnerId();

  const builder = new SignJWT({ partnerId, scope, email, partnerUserId })
    .setProtectedHeader({ alg: "RS256", kid, typ: "JWT" })
    .setIssuedAt()
    .setExpirationTime(`${ttlSeconds}s`);

  return builder.sign(key);
}
