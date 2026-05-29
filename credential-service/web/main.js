// Browser entry for the Aperture-on-Moca AIR Kit flow.
//
// Demonstrates the full client-side credential round-trip:
//   1. AIR Kit login (AIR Account smart wallet).
//   2. issueCredential -> issues an "Aperture Verified Agent" credential whose
//      subject is built from REAL on-chain compliance data (ZK-gated payment
//      count from ComplianceEscrow), fetched from this service's /subject.
//   3. verifyCredential -> ZK-verifies the credential against the dashboard
//      verification program and reports Compliant / Non-Compliant.
//
// Partner JWTs are minted by the backend (/authtoken) so the RSA private key
// never reaches the browser.

import { AirService, BUILD_ENV } from "@mocanetwork/airkit";

const $ = (id) => document.getElementById(id);
const log = (msg) => {
  const el = $("log");
  const line = typeof msg === "string" ? msg : JSON.stringify(msg, null, 2);
  el.textContent += line + "\n";
  el.scrollTop = el.scrollHeight;
};

let airService = null;
let cfg = null;
let loggedInAddress = null;

async function loadConfig() {
  if (cfg) return cfg;
  const operator = $("operator").value.trim();
  cfg = await fetch(`/subject?operator=${operator}`, {
    headers: { "ngrok-skip-browser-warning": "true" },
  }).then((r) => r.json());
  if (cfg.error) throw new Error(cfg.error);
  $("partnerId").value = cfg.partnerId;
  return cfg;
}

async function authToken(scope) {
  const email = $("email").value.trim();
  if (!email) throw new Error("enter the AIR Account email first");
  const res = await fetch(`/authtoken?email=${encodeURIComponent(email)}&scope=${scope}`, {
    headers: { "ngrok-skip-browser-warning": "true" },
  }).then((r) => r.json());
  if (res.error) throw new Error(res.error);
  return res.token;
}

async function ensureService() {
  await loadConfig();
  if (!airService) {
    const partnerId = $("partnerId").value.trim();
    airService = new AirService({ partnerId });
    await airService.init({ buildEnv: BUILD_ENV.SANDBOX, enableLogging: true, skipRehydration: false });
    log(`init ok (buildEnv=SANDBOX). isLoggedIn=${airService.isLoggedIn}`);
  }
  return airService;
}

async function login() {
  const s = await ensureService();
  if (!s.isLoggedIn) {
    const r = await s.login();
    log({ login: r });
    loggedInAddress = r?.abstractAccountAddress ?? loggedInAddress;
  }
  if (!loggedInAddress) {
    // fall back to reading from the service if available
    loggedInAddress = s.abstractAccountAddress ?? s.address ?? loggedInAddress;
  }
  log(`logged in. isLoggedIn=${s.isLoggedIn} account=${loggedInAddress ?? "?"}`);
}

async function issue() {
  const s = await ensureService();
  if (!s.isLoggedIn) await login();
  const operator = $("operator").value.trim();
  // Hold the credential under the logged-in AIR Account; attest the operator's
  // on-chain compliance as separate subject fields.
  const subjectId = loggedInAddress ? `did:pkh:eip155:222888:${loggedInAddress}` : undefined;
  const url = `/subject?operator=${operator}` + (subjectId ? `&subjectId=${encodeURIComponent(subjectId)}` : "");
  const c = await fetch(url, { headers: { "ngrok-skip-browser-warning": "true" } }).then((r) => r.json());
  if (c.error) throw new Error(c.error);
  log("credentialSubject (from on-chain compliance data):");
  log(c.subject);
  const token = await authToken("issue");
  const result = await s.issueCredential({
    authToken: token,
    credentialId: c.issuanceProgramId,
    credentialSubject: c.subject,
    issuerDid: c.issuerDid,
  });
  log("issueCredential OK:");
  log(result ?? "(no return value)");
}

async function verify() {
  const s = await ensureService();
  if (!s.isLoggedIn) await s.login();
  const c = await loadConfig();
  const token = await authToken("verify");
  const result = await s.verifyCredential({
    authToken: token,
    programId: c.verificationProgramId,
    redirectUrl: window.location.origin,
  });
  log("verifyCredential result:");
  log(result);
  if (result && result.status) log(`>>> STATUS: ${result.status}`);
}

function describeError(e) {
  if (!e) return "(empty error)";
  if (typeof e === "string") return e;
  const parts = [];
  if (e.name) parts.push(`name=${e.name}`);
  if (e.message) parts.push(`message=${e.message}`);
  if (e.code !== undefined) parts.push(`code=${e.code}`);
  if (e.status !== undefined) parts.push(`status=${e.status}`);
  // Pull own + inherited enumerable-ish props the SDK may attach.
  const own = {};
  for (const k of Object.getOwnPropertyNames(e)) {
    if (["stack"].includes(k)) continue;
    try { own[k] = e[k]; } catch {}
  }
  const ownStr = JSON.stringify(own);
  if (ownStr && ownStr !== "{}") parts.push(`props=${ownStr}`);
  try {
    const all = JSON.stringify(e, Object.getOwnPropertyNames(e));
    if (all && all !== "{}" && all !== ownStr) parts.push(`all=${all}`);
  } catch {}
  if (e.cause) parts.push(`cause=${describeError(e.cause)}`);
  if (parts.length === 0) parts.push("toString=" + String(e));
  return parts.join(" | ");
}

function wire(id, fn) {
  $(id).addEventListener("click", () => {
    fn().catch((e) => {
      log("ERROR: " + describeError(e));
      // Full object to the browser console for the SDK's own detail.
      console.error("[aperture] action failed:", e);
    });
  });
}

wire("btnLogin", login);
wire("btnIssue", issue);
wire("btnVerify", verify);
loadConfig().then((c) => log(`config loaded. partnerId=${c.partnerId}`)).catch((e) => log("config error: " + e.message));
