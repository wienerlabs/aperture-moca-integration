import express from "express";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { getPublicJwks } from "./keys.mjs";
import { issueOnBehalf, getStatus } from "./issue.mjs";
import { signPartnerJwt } from "./jwt.mjs";
import { buildCredentialSubject } from "./compliance.mjs";
import { config } from "./config.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

const app = express();
app.use(express.json());
// ngrok-free shows a browser interstitial unless this header is present; the
// AIR Kit page sets it on its own fetches, and serving it here is harmless.
app.use((_req, res, next) => {
  res.setHeader("ngrok-skip-browser-warning", "true");
  next();
});

/// Public JWKS endpoint. Register `<public-host>/.well-known/jwks.json` in the
/// dashboard (Account -> General Settings -> JWKS URL).
app.get("/.well-known/jwks.json", async (_req, res) => {
  try {
    res.json(await getPublicJwks());
  } catch (e) {
    res.status(500).json({ error: String(e.message ?? e) });
  }
});

app.get("/healthz", (_req, res) => res.json({ ok: true }));

/// Minimal privacy policy + terms pages so the partner dashboard form (which
/// requires a Privacy Policy URL) can be completed for the testnet integration.
const PAGE = (title, body) =>
  `<!doctype html><html lang="en"><head><meta charset="utf-8">` +
  `<meta name="viewport" content="width=device-width, initial-scale=1">` +
  `<title>${title}</title><style>body{font-family:system-ui,sans-serif;max-width:48rem;` +
  `margin:3rem auto;padding:0 1rem;line-height:1.6;color:#222}h1{font-size:1.5rem}` +
  `code{background:#f3f3f3;padding:.1rem .3rem;border-radius:.2rem}</style></head>` +
  `<body><h1>${title}</h1>${body}<hr><p><small>Aperture on Moca Chain, testnet ` +
  `integration. Contact: makinci473@gmail.com</small></p></body></html>`;

app.get("/privacy", (_req, res) => {
  res.type("html").send(
    PAGE(
      "Privacy Policy",
      `<p>This service is a testnet integration between Aperture and Moca Network's
      AIR Kit. It issues verifiable "Aperture Verified Agent" credentials on behalf
      of operators using the Moca sandbox APIs.</p>
      <p><strong>Data we process.</strong> To issue a credential we process the
      operator's wallet address, an AIR Account email supplied for issuance, and
      on-chain compliance data (the number of ZK-gated payments an operator has
      completed). We do not collect analytics or track users.</p>
      <p><strong>How it is used.</strong> These values populate the credential
      subject and are submitted to Moca's sandbox issuance API. The signing key
      used for Partner JWTs is held server-side and never shared; only its public
      half is published at <code>/.well-known/jwks.json</code>.</p>
      <p><strong>Retention.</strong> This is an ephemeral testnet deployment. No
      personal data is persisted beyond the lifetime of a request.</p>
      <p><strong>Contact.</strong> Questions about this testnet integration can be
      sent to makinci473@gmail.com.</p>`,
    ),
  );
});

app.get("/terms", (_req, res) => {
  res.type("html").send(
    PAGE(
      "Terms of Service",
      `<p>This is experimental testnet software provided as-is, without warranty,
      for evaluation of the Aperture and Moca Network AIR Kit integration. It does
      not handle mainnet assets and must not be relied upon for production use.</p>`,
    ),
  );
});

/// Issue an Aperture Verified Agent credential to an AIR Account (by email),
/// filling credentialSubject from real on-chain compliance data.
app.post("/issue", async (req, res) => {
  try {
    const { email, operatorAddress, agentId, subjectId, onDuplicate } = req.body ?? {};
    if (!email || !operatorAddress) {
      return res.status(400).json({ error: "email and operatorAddress are required" });
    }
    const credentialSubject = await buildCredentialSubject({ operatorAddress, agentId, subjectId });
    const result = await issueOnBehalf({ email, credentialSubject, onDuplicate });
    res.status(result.status).json({ credentialSubject, response: result.body });
  } catch (e) {
    res.status(500).json({ error: String(e.message ?? e) });
  }
});

app.get("/status", async (req, res) => {
  try {
    const { coreClaimHash, email } = req.query;
    if (!coreClaimHash || !email) {
      return res.status(400).json({ error: "coreClaimHash and email query params are required" });
    }
    const result = await getStatus({ coreClaimHash: String(coreClaimHash), email: String(email) });
    res.status(result.status).json(result.body);
  } catch (e) {
    res.status(500).json({ error: String(e.message ?? e) });
  }
});

/// Mint a short-lived Partner JWT for the browser AIR Kit flow. The private
/// key stays server-side; the browser only receives the signed token. `scope`
/// defaults to "issue" (client-side issueCredential); pass "verify" for the
/// verification flow.
app.get("/authtoken", async (req, res) => {
  try {
    const email = String(req.query.email ?? "");
    const scope = String(req.query.scope ?? "issue");
    if (!email) return res.status(400).json({ error: "email query param is required" });
    const token = await signPartnerJwt({ email, scope });
    res.json({ token, partnerId: config.partnerId() });
  } catch (e) {
    res.status(500).json({ error: String(e.message ?? e) });
  }
});

/// Build the credentialSubject from real on-chain compliance data.
app.get("/subject", async (req, res) => {
  try {
    const operatorAddress = String(req.query.operator ?? "");
    if (!operatorAddress) return res.status(400).json({ error: "operator query param is required" });
    const subject = await buildCredentialSubject({
      operatorAddress,
      agentId: req.query.agentId ? String(req.query.agentId) : undefined,
      subjectId: req.query.subjectId ? String(req.query.subjectId) : undefined,
    });
    res.json({
      subject,
      issuerDid: config.issuerDid(),
      issuanceProgramId: config.issuanceProgramId(),
      verificationProgramId: process.env.MOCA_VERIFICATION_PROGRAM_ID,
      partnerId: config.partnerId(),
    });
  } catch (e) {
    res.status(500).json({ error: String(e.message ?? e) });
  }
});

// Serve the bundled AIR Kit browser app (login + issue + verify).
app.use(express.static(resolve(__dirname, "..", "public")));

const port = Number(process.env.CREDENTIAL_SERVICE_PORT ?? 3010);
app.listen(port, () => {
  console.log(`credential-service listening on http://localhost:${port}`);
  console.log(`  JWKS:   http://localhost:${port}/.well-known/jwks.json`);
  const pub = config.jwksPublicUrl();
  if (pub) console.log(`  public: ${pub.replace(/\/+$/, "")}/.well-known/jwks.json  (register this in the dashboard)`);
  else console.log("  set MOCA_JWKS_PUBLIC_URL to your tunnel/deploy host, then register <host>/.well-known/jwks.json");
});
