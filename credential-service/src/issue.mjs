import { signPartnerJwt } from "./jwt.mjs";
import { config } from "./config.mjs";

/// Issue an "Aperture Verified Agent" credential on behalf of the AIR Account
/// identified by `email`. credentialSubject must satisfy the dashboard schema.
/// Returns the parsed JSON response (carries coreClaimHash on success).
export async function issueOnBehalf({ email, credentialSubject, onDuplicate = "ignore" }) {
  const jwt = await signPartnerJwt({ email, scope: "issue on-behalf" });
  const url = `${config.sandboxApi()}/credentials/issue-on-behalf`;

  const body = {
    issuerDid: config.issuerDid(),
    credentialId: config.issuanceProgramId(),
    credentialSubject,
    onDuplicate,
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-partner-auth": jwt,
    },
    body: JSON.stringify(body),
  });

  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = { raw: text };
  }
  return { status: res.status, ok: res.ok, body: json };
}

/// Poll issuance status by coreClaimHash.
export async function getStatus({ coreClaimHash, email }) {
  const jwt = await signPartnerJwt({ email, scope: "issue on-behalf" });
  const url = `${config.sandboxApi()}/credentials/status?coreClaimHash=${encodeURIComponent(coreClaimHash)}`;
  const res = await fetch(url, { headers: { "x-partner-auth": jwt } });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = { raw: text };
  }
  return { status: res.status, ok: res.ok, body: json };
}
