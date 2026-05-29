// @ts-expect-error - prover-ffi is plain ESM JS without type declarations.
import { generateProof as generateProofRaw } from "aperture-moca-prover-ffi";
import type { Address, Hex } from "viem";

export interface PaymentProof {
  a: readonly [bigint, bigint];
  b: readonly [readonly [bigint, bigint], readonly [bigint, bigint]];
  c: readonly [bigint, bigint];
  pubSignals: readonly [
    bigint, bigint, bigint, bigint, bigint,
    bigint, bigint, bigint, bigint, bigint,
  ];
  policyDataHash: Hex;
}

export interface ProveParams {
  recipient: Address;
  token: Address;
  amount: bigint;
  timestamp: bigint;
  dailyBefore?: bigint;
}

const toBig = (x: string | bigint): bigint => BigInt(x);

/// Generate a real Groth16 compliance proof bound to the EVM payment params,
/// returned in the bigint shape viem's contract calls expect.
export async function generatePaymentProof(params: ProveParams): Promise<PaymentProof> {
  const raw = await generateProofRaw({
    recipient: params.recipient,
    token: params.token,
    amount: params.amount.toString(),
    timestamp: params.timestamp.toString(),
    dailyBefore: (params.dailyBefore ?? 0n).toString(),
  });

  const pub = (raw.pubSignals as string[]).map(toBig);
  if (pub.length !== 10) throw new Error(`expected 10 public signals, got ${pub.length}`);

  const pubSignals: PaymentProof["pubSignals"] = [
    pub[0], pub[1], pub[2], pub[3], pub[4],
    pub[5], pub[6], pub[7], pub[8], pub[9],
  ];
  const policyDataHash = ("0x" + pub[1].toString(16).padStart(64, "0")) as Hex;

  return {
    a: [toBig(raw.a[0]), toBig(raw.a[1])],
    b: [
      [toBig(raw.b[0][0]), toBig(raw.b[0][1])],
      [toBig(raw.b[1][0]), toBig(raw.b[1][1])],
    ],
    c: [toBig(raw.c[0]), toBig(raw.c[1])],
    pubSignals,
    policyDataHash,
  };
}
