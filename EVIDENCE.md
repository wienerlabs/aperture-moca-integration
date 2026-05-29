# Evidence: Aperture on Moca Chain testnet

All artifacts below are real and reproducible on Moca Chain testnet (chain id
222888, explorer https://testnet-scan.mocachain.org). All listed transactions confirmed on-chain with status 1, the
43-test suite re-run green, and the 503/catalog endpoints re-checked.

## Deployed contracts

| Contract | Address |
|----------|---------|
| Groth16Verifier (from real `payment.zkey`) | [`0x6F1FEb4D4051A994638298c5E3cc0cEdC50B8ee5`](https://testnet-scan.mocachain.org/address/0x6F1FEb4D4051A994638298c5E3cc0cEdC50B8ee5) |
| PolicyRegistry | [`0x9aa8f0bfb9f2f6246F54A5B017c97AE6aa89bCD0`](https://testnet-scan.mocachain.org/address/0x9aa8f0bfb9f2f6246F54A5B017c97AE6aa89bCD0) |
| ComplianceEscrow v2 (gasless EIP-712) | [`0x276E394A95a3e8407497262d154b8dB415d9b4E1`](https://testnet-scan.mocachain.org/address/0x276E394A95a3e8407497262d154b8dB415d9b4E1) |
| ComplianceEscrow v1 | [`0x786F0935299D1A15f585D42Edf8c4e451B48FEA7`](https://testnet-scan.mocachain.org/address/0x786F0935299D1A15f585D42Edf8c4e451B48FEA7) |
| TestERC20 (atUSD, real ERC-20) | [`0xae9DBb6F08aD1D24BFC2698a4C5A32A9A472FFfb`](https://testnet-scan.mocachain.org/address/0xae9DBb6F08aD1D24BFC2698a4C5A32A9A472FFfb) |
| AgentRegistry (DID resolver) | [`0xE943CdBe65EE680749C344890278a5758Ee52780`](https://testnet-scan.mocachain.org/address/0xE943CdBe65EE680749C344890278a5758Ee52780) |

Operator / deployer: `0xF63CCda7f67B1a2b1F767705d61b2146563479EC`

## Live transactions

| What | Tx |
|------|----|
| Groth16Verifier deploy | [`0x1c3e0957...f64d6d69`](https://testnet-scan.mocachain.org/tx/0x1c3e095762f208e7338ca98ea154c68734efc166648d58dd05dd4238f64d6d69) |
| PolicyRegistry deploy | [`0x9320fba7...cecf35105`](https://testnet-scan.mocachain.org/tx/0x9320fba786894ed78b9a5b64dde752fc6b15368c039781b0744f882cecf35105) |
| ComplianceEscrow v1 deploy | [`0x7f388541...e05b630b`](https://testnet-scan.mocachain.org/tx/0x7f3885413344cb19b9088098e1d0d1f634fc930e7caed70de66e0ec5e05b630b) |
| ComplianceEscrow v2 deploy | [`0x69adb455...f9a46b4a`](https://testnet-scan.mocachain.org/tx/0x69adb455f9a83f48fdc93fe0f5ef2f3ecd691ece9f0a8c3f4c1499b5f9a46b4a) |
| AgentRegistry deploy | [`0x942d1622...24ea7f5a`](https://testnet-scan.mocachain.org/tx/0x942d16229f816ef681e7fab71e9419738d5ab4681d8b6d54925e724724ea7f5a) |
| TestERC20 deploy | [`0x6c9c2544...549bd2592`](https://testnet-scan.mocachain.org/tx/0x6c9c25445960929245e6d1312c7a48dd10c2e99c030b0d21310813c549bd2592) |
| initializeOperator | [`0x39a97afd...c199ffa378`](https://testnet-scan.mocachain.org/tx/0x39a97afda29f0bba2dfdb39b647a3415a3af68ae6d624ad6892607c199ffa378) |
| registerPolicy | [`0x41c35797...d4607a318`](https://testnet-scan.mocachain.org/tx/0x41c357975bf931626138d5f9940c1045737d825e83f4535dce20bb1d4607a318) |
| deposit (lock) | [`0xc2557067...e4267894`](https://testnet-scan.mocachain.org/tx/0xc2557067d37425420f362fe9fc3fe372da071be9fcf620fa3844ba62e4267894) |
| **ZK-gated release (cast)** | [`0x302fe4f9...424ea366f`](https://testnet-scan.mocachain.org/tx/0x302fe4f98ae942abd2bc4c1f837da8447d7953781b5b7588e6e3391424ea366f) |
| **ZK-gated release (viem client)** | [`0xaf1c78fc...68dee920`](https://testnet-scan.mocachain.org/tx/0xaf1c78fc9b82e7fc48d44b950655fafa247dd860bb591b21fe4ffddc68dee920) |
| **Gasless release (EIP-712 meta-tx, relayer-submitted)** | [`0x096bdfeb...8f41dfe3`](https://testnet-scan.mocachain.org/tx/0x096bdfeb8b35b5cc3a019c9207f7ef38c31c2654449b831db34ed09f8f41dfe3) |
| AgentRegistry DID register | [`0x72ce52b5...f10d6291`](https://testnet-scan.mocachain.org/tx/0x72ce52b5dcbd0da36a8859d3f6c950b26507b45c7efc714a9d072479f10d6291) |

Notable results, readable on the explorer / via the client:
- ZK-gated release: a real Groth16 proof from `payment.circom` was verified
  on-chain and released 5 atUSD to `0x...bEEF`.
- Gasless release: the operator signed an EIP-712 `PaymentAuthorization`
  off-chain and a separate relayer submitted it; the operator's native MOCA
  balance was unchanged by the payment.
- DID resolution: `did:moca:aperture-agent-1` resolves over the Moca RPC to the
  operator account `0xF63CCda7f67B1a2b1F767705d61b2146563479EC`, the account
  whose ZK-gated payments are recorded in `ComplianceEscrow`.

## Test suite

`forge test --ffi` (escrow tests generate real Groth16 proofs via FFI):

```
Ran 3 test suites: 43 tests passed, 0 failed, 0 skipped
  PolicyRegistry.t.sol      20 passed
  ComplianceEscrow.t.sol    13 passed   (real proofs + gasless EIP-712 path)
  AgentRegistry.t.sol       10 passed
```

## AIR Kit (Faz 1 and 2)

- AIR Account login works: a real AIR Account smart wallet
  (`0x5a8bb276f77360b3fBEc25285594d159B846F0f1`) logged in, and the dashboard
  signin now offers AIR Account login alongside wallet login.
- Partner JWT + JWKS are validated by AIR: the REST issue-on-behalf call
  advanced from `401 Invalid x-partner-auth` to `403 issueOnBehalf is not
  allowed` once the JWKS was registered, proving the signature/JWKS chain works.

## Moca-side blockers (not our integration)

These are verified directly with curl, independent of any browser, so they are
not CORS or client artifacts. Our integration code is complete and waits on
these Moca services.

Captured 2026-05-29 22:27 UTC:

```
# AIR Kit credential subsystem - HTTP 503 (AWS ALB: no healthy backend)
GET https://credential-widget.sandbox.air3.com/        -> HTTP 503
GET https://credential.api.sandbox.air3.com/           -> HTTP 503
GET https://credential-moca.api.sandbox.air3.com/      -> HTTP 503
```

- **Faz 2 (issue/verify round-trip):** blocked. The AIR Kit credential service
  is not serving (503). Our JWKS, Partner JWT, on-chain-derived credentialSubject
  and both the server-side and client-side issuance paths are implemented. When
  Moca brings the credential service online we will wire it through and validate
  end to end; some adjustments may be needed once the live API behavior is
  observable.

## Catalog API (Bonus) - working

The catalog is NOT on the `api.*.mocachain.org/v1` host (those `/catalog/*`
routes return 404). It is served from the credential API host. Verified live
2026-05-29:

```
GET https://api.sandbox.mocachain.org/v1/catalog/programs            -> HTTP 403/404 (no catalog on this host; code varies by gateway)
GET https://credential-testnet.api.sandbox.air3.com/catalog/schemas  -> HTTP 200 (total 90)
GET https://credential-testnet.api.sandbox.air3.com/catalog/programs -> HTTP 200 (total 91)
```

`moca/credential-service` includes a read-only catalog reader
(`npm run catalog`) that browses ecosystem schemas and programs against this
live endpoint. Our own "Aperture Verified Agent" schema
(`01KSTQK70XGFBT558HRHFB`) is not listed in the public catalog (the API returns
"Schema not found" for it), which is expected since it has not been published to
the catalog.
