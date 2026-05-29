// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IGroth16Verifier
/// @notice Interface for the snarkjs-generated `Groth16Verifier` produced from
///         the Aperture `payment.circom` circuit via
///         `snarkjs zkey export solidityverifier payment.zkey`. The 10-element
///         `_pubSignals` array is the circuit's public output vector, in order:
///         [0] is_compliant, [1] policy_data_hash, [2] recipient_high,
///         [3] recipient_low, [4] amount, [5] token_mint_high,
///         [6] token_mint_low, [7] daily_spent_before, [8] current_unix_timestamp,
///         [9] stripe_receipt_hash.
interface IGroth16Verifier {
    function verifyProof(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[10] calldata pubSignals
    ) external view returns (bool);
}
