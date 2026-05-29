# Aperture on Moca Chain

This directory holds the port of Aperture's ZK policy-compliance payment layer
from Solana to Moca Chain (an EVM, Evmos-based L1, testnet chain id 222888).

Aperture gates every autonomous AI-agent payment behind a Groth16 proof that the
payment satisfies the operator's compliance policy (per-transaction cap, daily
cap, token whitelist, recipient blocklist, category and time rules). On Solana
this is enforced by Anchor programs plus an alt_bn128 verifier. This port moves
the same enforcement to Moca Chain, where the EVM bn128 pairing precompiles
(EIP-196/197) verify the very same circuit.

## How Moca is used

The compliance proof is produced by the unchanged `payment.circom` circuit and
its existing snarkjs proving key. We generate the Solidity verifier directly
from that key (`snarkjs zkey export solidityverifier payment.zkey`), so the
on-chain verifier on Moca Chain checks byte-for-byte the same statement the
Solana verifier did. The policy commitments live in `PolicyRegistry` on Moca
Chain, and `ComplianceEscrow` releases ERC-20 funds only after the proof
verifies and its public signals (recipient, token, amount, policy hash, daily
spend, timestamp) are bound to the actual transfer. Identity and credentials
(Faz 1-2) use Moca's AIR Kit (`@mocanetwork/airkit`), while the agent DID
resolver (Faz 3) is an on-chain registry on Moca: the operator logs in with
an AIR Account smart wallet (working live). The "compliant operator" credential
(credentialSubject built from on-chain compliance data, plus ZK verification) is
fully implemented against Moca's sandbox APIs, but the end-to-end issue/verify
round-trip is pending Moca's credential service, which currently returns HTTP
503 (see EVIDENCE.md).

Honest boundary: by design, AIR Kit credential verification is client-side and
settles on Moca Chain, and the contract enforcement also runs on Moca Chain, so
the link between credential and enforcement is native to Moca Chain rather than a
cross-chain bridge. The contract enforcement (Faz 3-5) is live; the credential
verification half (Faz 2) is implemented but not yet exercised end to end because
Moca's credential service is down (503).

## Layout

```
contracts/          Foundry project (Solidity + tests)
  src/
    PolicyRegistry.sol      Faz 4: operator + policy registry (port of the Anchor program)
    Groth16Verifier.sol     Faz 5: generated from artifacts/payment.zkey
    IGroth16Verifier.sol    Verifier interface
    ComplianceEscrow.sol    Faz 5: ZK-gated lock / release / refund escrow
    AgentRegistry.sol       Faz 3: agent DID to EVM smart-account resolver
  test/                     forge tests (registry + escrow with real proofs + agent registry)
  script/Deploy.s.sol       testnet deployment
prover-ffi/         Real Groth16 proof generator (wraps the unchanged circuit artifacts)
client/             viem TypeScript client (operator/policy, escrow, ZK-gated pay)
credential-service/ AIR Kit: JWKS, Partner JWT, issue/verify web app, catalog reader
artifacts/          payment.circom proving artifacts (wasm, zkey, vk) used by the prover
dashboard-integration/  AIR Account login patches for the main Aperture dashboard
```

## TypeScript client (viem)

`client` wraps the deployed contracts and the prover behind one class.

```bash
cd client
npm install
npm run pay        # live end-to-end example reading the repo-root .env
```

```ts
import { ApertureMocaClient } from "@aperture/moca-client";

const client = new ApertureMocaClient({
  privateKey: process.env.MOCA_DEPLOYER_PRIVATE_KEY as `0x${string}`,
  addresses: {
    policyRegistry: process.env.MOCA_POLICY_REGISTRY as `0x${string}`,
    complianceEscrow: process.env.MOCA_COMPLIANCE_ESCROW as `0x${string}`,
  },
});

// Generates a real Groth16 proof bound to (recipient, token, amount), fetches
// the block timestamp and effective daily spend automatically, and releases.
const { txHash } = await client.payWithProof({
  policyId, token, recipient, amount: 5_000_000n,
});
```

A second live release was executed through this client:
[`0xaf1c78fc...68dee920`](https://testnet-scan.mocachain.org/tx/0xaf1c78fc9b82e7fc48d44b950655fafa247dd860bb591b21fe4ffddc68dee920).

## Phase status

| Phase | Scope | Status |
|-------|-------|--------|
| 0 | Verify env, RPC, SDK, toolchain | Done |
| 4 | PolicyRegistry to Solidity | Done, 20 tests passing |
| 5a | Real Groth16 verifier + escrow + public-input binding | Done, 13 end-to-end tests passing |
| 5b | x402 to EIP-712 signed release + gasless (relayer-submitted meta-tx) | Done; demonstrated live |
| 4/5 | Testnet deploy + explorer links + viem TS client | Done; deployed and demonstrated live |
| 1 | AIR Kit login | Done; real AIR Account login working, integrated into the dashboard signin |
| 2 | Agent credential issue + verify | Infra complete; blocked on Moca sandbox credential API outage (HTTP 503) |
| 3 | DID resolver to Moca RPC | Done; deployed and resolving live |
| Bonus | Catalog API ecosystem browse (read-only) | Done; live against the credential API host |

### AIR Kit identity layer (Faz 1 and 2)

`credential-service` hosts the public JWKS, signs Partner JWTs, and serves
a browser app (`web/`, bundled to `public/`) that logs in with an AIR Account
(working) and attempts the issue/verify round-trip (currently blocked by Moca's
503, see below). credentialSubject is built from real
on-chain data: the operator's ZK-gated payment count read from
`ComplianceEscrow` drives `compliantPaymentCount` and `reputationScore`.

Status, verified directly:

- Faz 1 login works. A real AIR Account smart wallet
  (`0x5a8bb276f77360b3fBEc25285594d159B846F0f1`, which lists Moca chain 222888
  among its chains) logged in through the app.
- The main dashboard now offers AIR Account login too. An additive `air`
  NextAuth provider (`dashboard/src/lib/auth.ts`) plus a "Sign in with AIR
  Account" button (`dashboard/src/app/auth/signin/page.tsx`) and a CDN-loaded
  helper (`dashboard/src/lib/airkit-login.ts`) sit alongside the existing
  wallet login. The SDK loads from an ESM CDN at click time, so the dashboard
  build gains no bundled dependency and the change is fully removable.
- The JWKS is registered in the dashboard and the Partner JWT validates (the
  REST issue-on-behalf call advanced past auth from 401 to 403).
- Server-side `issue-on-behalf` is not enabled for this sandbox partner (403
  `issueOnBehalf is not allowed`, no enable toggle present), so the flow uses
  the client-side `issueCredential`.
- Hosting note: during development the JWKS and the AIR Kit page are exposed
  through an ngrok tunnel, whose URL is ephemeral. The JWKS URL registered in
  the dashboard points at that tunnel and will change if the tunnel restarts.
  For a stable deployment the credential-service (JWKS + page) should be hosted
  on a permanent host (for example Vercel or Railway) and that URL registered
  in the dashboard.
- The issue and verify round-trip is currently blocked by a Moca-side outage:
  the AIR Kit credential subsystem returns HTTP 503 across
  `credential-widget.sandbox.air3.com`, `credential.api.sandbox.air3.com` and
  `credential-moca.api.sandbox.air3.com` (confirmed by direct curl, independent
  of the browser; see EVIDENCE.md for timestamped output). The integration is
  complete on our side; once Moca's credential service is live we will wire the
  round-trip through and validate it end to end. Some adjustments may be needed
  when the live API behavior becomes observable, so this is not claimed as
  zero-change.

### DID resolver on Moca (Faz 3)

`AgentRegistry.sol` is an on-chain agent identity registry on Moca. It mirrors
the agent-identity resolution Aperture used on Solana (where a DID resolved to a
wallet pubkey over the Solana RPC); here the resolution runs over the Moca
testnet RPC and maps a DID to an EVM smart-account, with a reverse index from
address back to DID.

Demonstrated live on Moca testnet: the DID `did:moca:aperture-agent-1` resolves
to the operator's on-chain account
(`0xF63CCda7f67B1a2b1F767705d61b2146563479EC`), the same account whose ZK-gated
payments are recorded in `ComplianceEscrow`, so an agent identity maps directly
to its verifiable on-chain compliance history.

```bash
cd client
npm run resolve            # resolves did:moca:aperture-agent-1 over Moca RPC
```

```ts
const smartAccount = await client.resolveSmartAccount("did:moca:aperture-agent-1");
const did = await client.didOf(smartAccount); // reverse resolution
```

## Catalog browse (Bonus)

The AIR Kit ecosystem catalog is live and read-only. It is NOT on the
`api.*.mocachain.org/v1` host (those `/catalog/*` routes return 403/404); it is
served from the credential API host (`MOCA_CATALOG_API`, default
`https://credential-testnet.api.sandbox.air3.com`). `credential-service`
includes a reader:

```bash
cd credential-service
npm run catalog            # lists ecosystem schemas + programs (live, no auth)
npm run catalog search kyc
```

Verified live (2026-05-29): 90 schemas and 91 programs returned from the catalog.

## Build and test

Prerequisites: Foundry, Node.js, and the circuit artifacts at
`artifacts/` (payment.wasm, payment.zkey).

```bash
# 1. Solidity dependencies (forge-std, OpenZeppelin) via Soldeer
cd contracts
forge soldeer install

# 2. Proof generator dependencies
cd ../prover-ffi
npm install

# 3. Run all tests. --ffi is required: the escrow tests shell out to the real
#    prover to produce genuine Groth16 proofs, then verify them on-chain.
cd ../contracts
forge test --ffi -vv
```

Expected: `43 tests passed` (20 PolicyRegistry, 13 ComplianceEscrow, 10 AgentRegistry).

## Public-input binding

The circuit exposes 10 public signals, in order: `is_compliant`,
`policy_data_hash`, `recipient_high`, `recipient_low`, `amount`,
`token_mint_high`, `token_mint_low`, `daily_spent_before`,
`current_unix_timestamp`, `stripe_receipt_hash`.

`ComplianceEscrow.releaseWithProof` reproduces every check the Solana
`verify_payment_v2_with_transfer` instruction performed before its token CPI:

1. Groth16 verification with the generated verifier.
2. `is_compliant == 1`.
3. `policy_data_hash` equals the active policy hash in `PolicyRegistry`.
4. `daily_spent_before` equals the operator's effective on-chain daily spend,
   which resets at UTC midnight exactly like Solana `OperatorState`.
5. `current_unix_timestamp` within 60 seconds of block time.
6. `stripe_receipt_hash == 0` (pure-token flow; MPP proofs are rejected here).
7. recipient, token and amount byte-bound to the release. The circuit encodes
   addresses as a 256-bit value split into two 128-bit halves (built for Solana
   32-byte pubkeys); on EVM the reconstructed value must equal
   `uint256(uint160(addr))`, so a 20-byte address binds losslessly.

Amount and daily spend are constrained to fit 64 bits, matching the circuit's
`LessEqThan(64/65)` comparators.

## x402 on EVM: gasless signed release (Faz 5)

`ComplianceEscrow.releaseWithProofSigned` is the EVM adaptation of the x402
payment flow. Instead of an on-chain transfer signed by the payer, the operator
signs an EIP-712 `PaymentAuthorization` off-chain (the typed-data form of an
x402 payment header: token, recipient, amount, policy, nonce, deadline). A
relayer submits that authorization together with the Groth16 proof and pays the
gas. This is a relayer + EIP-712 meta-transaction (signature-based
authorization), not an ERC-4337 / AIR Kit Paymaster integration: the operator's
agent makes compliant payments without holding native MOCA because the relayer
covers gas. Replay is prevented by a sequential per-operator nonce and a
deadline, on top of the proof nullifier and daily-spend binding.

Demonstrated live: the operator signed off-chain and a separate relayer
submitted the release. The operator's native MOCA balance was unchanged by the
payment. Release tx:
[`0x096bdfeb...8f41dfe3`](https://testnet-scan.mocachain.org/tx/0x096bdfeb8b35b5cc3a019c9207f7ef38c31c2654449b831db34ed09f8f41dfe3).

```bash
cd client
npm run pay-gasless        # operator signs, relayer submits, operator pays no gas
```

## Deploy to Moca Chain testnet

Set a funded testnet key in the repo-root `.env` (never committed):

```
MOCA_DEPLOYER_PRIVATE_KEY=0x...        # funded via https://faucet.mocachain.org
MOCA_DEPLOY_TEST_TOKEN=true            # optional: also deploy a test stablecoin
```

```bash
cd contracts
forge script script/Deploy.s.sol:Deploy \
  --rpc-url https://rpc.testnet.mocachain.dev \
  --broadcast
```

Deployed to Moca Chain testnet (chain id 222888) on 2026-05-29. Explorer base:
https://testnet-scan.mocachain.org

| Contract | Address | Deploy tx |
|----------|---------|-----------|
| Groth16Verifier | [`0x6F1FEb4D4051A994638298c5E3cc0cEdC50B8ee5`](https://testnet-scan.mocachain.org/address/0x6F1FEb4D4051A994638298c5E3cc0cEdC50B8ee5) | [`0x1c3e0957...f64d6d69`](https://testnet-scan.mocachain.org/tx/0x1c3e095762f208e7338ca98ea154c68734efc166648d58dd05dd4238f64d6d69) |
| PolicyRegistry | [`0x9aa8f0bfb9f2f6246F54A5B017c97AE6aa89bCD0`](https://testnet-scan.mocachain.org/address/0x9aa8f0bfb9f2f6246F54A5B017c97AE6aa89bCD0) | [`0x9320fba7...cecf35105`](https://testnet-scan.mocachain.org/tx/0x9320fba786894ed78b9a5b64dde752fc6b15368c039781b0744f882cecf35105) |
| ComplianceEscrow (v2, gasless) | [`0x276E394A95a3e8407497262d154b8dB415d9b4E1`](https://testnet-scan.mocachain.org/address/0x276E394A95a3e8407497262d154b8dB415d9b4E1) | [`0x69adb455...f9a46b4a`](https://testnet-scan.mocachain.org/tx/0x69adb455f9a83f48fdc93fe0f5ef2f3ecd691ece9f0a8c3f4c1499b5f9a46b4a) (adds EIP-712 `releaseWithProofSigned`) |
| ComplianceEscrow (v1) | [`0x786F0935299D1A15f585D42Edf8c4e451B48FEA7`](https://testnet-scan.mocachain.org/address/0x786F0935299D1A15f585D42Edf8c4e451B48FEA7) | [`0x7f388541...e05b630b`](https://testnet-scan.mocachain.org/tx/0x7f3885413344cb19b9088098e1d0d1f634fc930e7caed70de66e0ec5e05b630b) |
| TestERC20 (atUSD) | [`0xae9DBb6F08aD1D24BFC2698a4C5A32A9A472FFfb`](https://testnet-scan.mocachain.org/address/0xae9DBb6F08aD1D24BFC2698a4C5A32A9A472FFfb) | [`0x6c9c2544...549bd2592`](https://testnet-scan.mocachain.org/tx/0x6c9c25445960929245e6d1312c7a48dd10c2e99c030b0d21310813c549bd2592) |
| AgentRegistry | [`0xE943CdBe65EE680749C344890278a5758Ee52780`](https://testnet-scan.mocachain.org/address/0xE943CdBe65EE680749C344890278a5758Ee52780) | (Faz 3 DID resolver) |

The ComplianceEscrow constructor was wired to the deployed verifier and
registry; verified on-chain via `verifier()` and `registry()` getters.

## Live on-chain demonstration

A full ZK-gated payment was executed on Moca Chain testnet end to end. A real
Groth16 proof from `payment.circom` was generated against the chain's current
block timestamp, verified by the deployed `Groth16Verifier`, and used to release
5 atUSD from the operator's escrow balance to the recipient. No part of this was
simulated.

| Step | Tx |
|------|----|
| initializeOperator | [`0x39a97afd...c199ffa378`](https://testnet-scan.mocachain.org/tx/0x39a97afda29f0bba2dfdb39b647a3415a3af68ae6d624ad6892607c199ffa378) |
| registerPolicy | [`0x41c35797...d4607a318`](https://testnet-scan.mocachain.org/tx/0x41c357975bf931626138d5f9940c1045737d825e83f4535dce20bb1d4607a318) |
| deposit (lock) | [`0xc2557067...e4267894`](https://testnet-scan.mocachain.org/tx/0xc2557067d37425420f362fe9fc3fe372da071be9fcf620fa3844ba62e4267894) |
| releaseWithProof (ZK-gated) | [`0x302fe4f9...424ea366f`](https://testnet-scan.mocachain.org/tx/0x302fe4f98ae942abd2bc4c1f837da8447d7953781b5b7588e6e3391424ea366f) |

- Operator: `0xF63CCda7f67B1a2b1F767705d61b2146563479EC`
- Recipient: `0x000000000000000000000000000000000000bEEF` (this release moved
  +5,000,000; the same address also received the viem +2,000,000 and gasless
  +1,000,000 demo releases, so its live balance is 8,000,000)
- Policy data hash committed and matched on-chain:
  `0x291899e218f2fcd54900f6211f8865f0d211f7f485b234b5dcea7dcb4b567ea0`
