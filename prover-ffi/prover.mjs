// Reusable real Groth16 proof generator for the Aperture -> Moca EVM port.
//
// `generateProof` builds a COMPLIANT witness for the unchanged payment.circom
// circuit (encoding EVM addresses the way the circuit expects), runs snarkjs
// groth16.fullProve against the real payment.wasm + payment.zkey artifacts, and
// returns the proof in the exact shape the Solidity Groth16Verifier consumes
// (with the snarkjs G2 coordinate swap already applied).
//
// There is no mock: the same proving key that secures the Solana deployment
// produces the proof, and the EVM verifier checks it. Consumed by the Foundry
// FFI tests (via prove.mjs) and by the viem TS client (via @import).

import { buildPoseidon } from 'circomlibjs';
import * as snarkjs from 'snarkjs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ARTIFACTS = resolve(__dirname, '..', 'artifacts');
const WASM = resolve(ARTIFACTS, 'payment.wasm');
const ZKEY = resolve(ARTIFACTS, 'payment.zkey');

const MAX_WHITELIST = 10;
const MAX_BLOCKED = 10;
const MAX_CATEGORIES = 8;
const MASK_128 = (1n << 128n) - 1n;

/// Blocked sentinel kept distinct from any real recipient so rule 4 passes.
const BLOCKED_SENTINEL = '0x000000000000000000000000000000000000dEaD';

function splitAddress(addrHex) {
  // EVM address -> the same 32-byte big-endian value the circuit splits into
  // two 128-bit halves: high = value >> 128, low = value & (2**128 - 1).
  const value = BigInt(addrHex);
  if (value > (1n << 160n) - 1n) throw new Error(`not a 160-bit address: ${addrHex}`);
  return [value >> 128n, value & MASK_128];
}

function padList(entries, maxLen) {
  const values = entries.map((e) => e.toString());
  const mask = entries.map(() => '1');
  while (values.length < maxLen) {
    values.push('0');
    mask.push('0');
  }
  return { values, mask };
}

/// Generate a real compliant proof bound to the given EVM payment parameters.
/// Returns { a:[2], b:[2][2], c:[2], pubSignals:[10] } as decimal strings, plus
/// the parsed numeric fields most callers need.
export async function generateProof({ recipient, token, amount, timestamp, dailyBefore = 0n }) {
  if (!recipient || !token) throw new Error('recipient and token are required');

  const amountB = BigInt(amount);
  const timestampB = BigInt(timestamp);
  const dailyB = BigInt(dailyBefore);

  const poseidon = await buildPoseidon();
  const F = poseidon.F;
  const fieldStr = (x) => F.toString(x);

  const [recipientHigh, recipientLow] = splitAddress(recipient);
  const [tokenHigh, tokenLow] = splitAddress(token);

  const tokenHash = fieldStr(poseidon([tokenHigh, tokenLow]));
  const tokens = padList([tokenHash], MAX_WHITELIST);

  const [bHigh, bLow] = splitAddress(BLOCKED_SENTINEL);
  if (bHigh === recipientHigh && bLow === recipientLow) {
    throw new Error('recipient collides with blocked sentinel');
  }
  const blockedHash = fieldStr(poseidon([bHigh, bLow]));
  const blocked = padList([blockedHash], MAX_BLOCKED);

  const category = fieldStr(poseidon([1n, 2n]));
  const cats = padList([category], MAX_CATEGORIES);

  const input = {
    max_per_tx_lamports: (1n << 62n).toString(),
    max_daily_lamports: (1n << 62n).toString(),
    token_whitelist: tokens.values,
    token_whitelist_mask: tokens.mask,
    blocked_addresses: blocked.values,
    blocked_addresses_mask: blocked.mask,
    allowed_categories: cats.values,
    allowed_categories_mask: cats.mask,
    payment_category: category,
    operator_id_field: fieldStr(poseidon([7n])),
    policy_id_field: fieldStr(poseidon([42n])),
    time_active: '0',
    time_days_bitmask: '0',
    time_start_hour_utc: '0',
    time_end_hour_utc: '0',
    recipient_high_in: recipientHigh.toString(),
    recipient_low_in: recipientLow.toString(),
    amount_lamports_in: amountB.toString(),
    token_mint_high_in: tokenHigh.toString(),
    token_mint_low_in: tokenLow.toString(),
    daily_spent_before_in: dailyB.toString(),
    current_unix_timestamp_in: timestampB.toString(),
    stripe_receipt_hash_in: '0',
  };

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, WASM, ZKEY);

  if (publicSignals[0] !== '1') {
    throw new Error(`circuit returned is_compliant=${publicSignals[0]} (expected 1)`);
  }
  if (publicSignals.length !== 10) {
    throw new Error(`expected 10 public signals, got ${publicSignals.length}`);
  }

  // Solidity calldata ordering: snarkjs swaps the two coordinates of each G2
  // (pi_b) pair relative to its internal representation.
  const a = [proof.pi_a[0], proof.pi_a[1]];
  const b = [
    [proof.pi_b[0][1], proof.pi_b[0][0]],
    [proof.pi_b[1][1], proof.pi_b[1][0]],
  ];
  const c = [proof.pi_c[0], proof.pi_c[1]];

  return {
    a,
    b,
    c,
    pubSignals: publicSignals,
    policyDataHash: BigInt(publicSignals[1]),
  };
}

/// ABI-encode (uint256[2],uint256[2][2],uint256[2],uint256[10]) as 0x-hex.
/// All types are static, so this is the 18 words concatenated in order.
export function encodeProofForSolidity({ a, b, c, pubSignals }) {
  const toHex32 = (x) => BigInt(x).toString(16).padStart(64, '0');
  const words = [
    a[0], a[1],
    b[0][0], b[0][1], b[1][0], b[1][1],
    c[0], c[1],
    ...pubSignals,
  ];
  return '0x' + words.map(toHex32).join('');
}
