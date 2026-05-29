#!/usr/bin/env node
// CLI wrapper around prover.mjs for Foundry FFI.
//
// Usage:
//   node prove.mjs <recipientAddr> <tokenAddr> <amount> <timestamp> <dailyBefore>
//
// Output (stdout): 0x-prefixed ABI encoding of
//   (uint256[2] a, uint256[2][2] b, uint256[2] c, uint256[10] pubSignals)

import { generateProof, encodeProofForSolidity } from './prover.mjs';

async function main() {
  const [recipient, token, amount, timestamp, dailyBefore] = process.argv.slice(2);
  if (!recipient || !token) {
    throw new Error('usage: prove.mjs <recipient> <token> <amount> <timestamp> <dailyBefore>');
  }
  const proof = await generateProof({
    recipient,
    token,
    amount: amount ?? '5000000',
    timestamp: timestamp ?? '1735689600',
    dailyBefore: dailyBefore ?? '0',
  });
  process.stdout.write(encodeProofForSolidity(proof));
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    process.stderr.write(String(err && err.stack ? err.stack : err) + '\n');
    process.exit(1);
  });
