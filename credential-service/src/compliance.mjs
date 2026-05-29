import { createPublicClient, http, getAddress } from "viem";
import { config } from "./config.mjs";

const escrowAbi = [
  {
    type: "function",
    name: "operatorState",
    stateMutability: "view",
    inputs: [{ name: "operator", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "dailySpent", type: "uint64" },
          { name: "dayStartUnix", type: "uint64" },
          { name: "totalReleases", type: "uint64" },
        ],
      },
    ],
  },
];

/// Build the credentialSubject for the "Aperture Verified Agent" schema using
/// REAL on-chain data: the number of ZK-gated releases the operator has made
/// through ComplianceEscrow drives compliantPaymentCount and the reputation
/// score. Nothing here is fabricated.
export async function buildCredentialSubject({ operatorAddress, agentId, subjectId }) {
  const operator = getAddress(operatorAddress);
  const escrow = config.complianceEscrow();
  if (!escrow) throw new Error("MOCA_COMPLIANCE_ESCROW not set; deploy the contracts first");

  const client = createPublicClient({ transport: http(config.rpcUrl()) });
  const state = await client.readContract({
    address: getAddress(escrow),
    abi: escrowAbi,
    functionName: "operatorState",
    args: [operator],
  });

  const compliantPaymentCount = Number(state.totalReleases);
  const complianceStatus = compliantPaymentCount > 0 ? "compliant" : "pending";
  // Reputation: a transparent, monotonic function of verified on-chain history.
  const reputationScore = Math.min(100, compliantPaymentCount * 10);

  return {
    id: subjectId ?? `did:pkh:eip155:${222888}:${operator}`,
    agentId: agentId ?? `aperture-agent:${operator}`,
    operatorAddress: operator,
    complianceStatus,
    compliantPaymentCount,
    reputationScore,
    verifiedAt: new Date().toISOString(),
  };
}
