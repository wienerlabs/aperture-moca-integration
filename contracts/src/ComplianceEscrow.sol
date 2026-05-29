// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IGroth16Verifier} from "./IGroth16Verifier.sol";
import {PolicyRegistry} from "./PolicyRegistry.sol";

/// @title ComplianceEscrow
/// @notice EVM port of Aperture's Solana `verify_payment_v2_with_transfer`
///         instruction for Moca Chain. An operator locks ERC-20 funds, then
///         releases them to a recipient only by presenting a Groth16 proof
///         from the `payment.circom` circuit. Every check the Solana handler
///         performed before its Token-2022 CPI is reproduced here before the
///         ERC-20 transfer, so the compliance envelope is identical:
///
///           1. Groth16 cryptographic verification (real verifier, not a stub).
///           2. is_compliant public signal == 1.
///           3. policy_data_hash public signal == the active policy's hash in
///              `PolicyRegistry` (cross-contract read).
///           4. daily_spent_before public signal == the operator's effective
///              on-chain daily spend (reset at UTC midnight).
///           5. current_unix_timestamp public signal within 60s of block time.
///           6. stripe_receipt_hash public signal == 0 (this is the pure-token
///              flow; MPP/Stripe proofs are rejected here).
///           7. recipient / token / amount public signals byte-bound to the
///              actual ERC-20 release. The circuit encodes addresses as a
///              256-bit value split into two 128-bit halves (it was built for
///              Solana 32-byte pubkeys); on EVM the reconstructed value must
///              equal `uint256(uint160(addr))`.
///
/// @dev Replay protection mirrors Solana: the timestamp window (60s) plus the
///      daily_spent_before binding (which moves forward after each release)
///      already bound a proof to a single moment. A keccak nullifier over the
///      full proof is added as defense in depth so the exact same proof cannot
///      be submitted twice even inside the tolerance window.
contract ComplianceEscrow is ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    // --------------------------------------------------------------------- //
    //                              Immutables                               //
    // --------------------------------------------------------------------- //

    IGroth16Verifier public immutable verifier;
    PolicyRegistry public immutable registry;

    // --------------------------------------------------------------------- //
    //                               Constants                               //
    // --------------------------------------------------------------------- //

    /// @dev Mirrors `OperatorState::SECONDS_PER_DAY` on Solana.
    uint256 public constant SECONDS_PER_DAY = 86_400;

    /// @dev Mirrors `TIMESTAMP_TOLERANCE_SECONDS` on Solana.
    uint256 public constant TIMESTAMP_TOLERANCE = 60;

    /// @dev The circuit's range checks (`LessEqThan(64)`) assume amount and
    ///      daily-spend fit in 64 bits; enforce that on-chain so a field
    ///      element above the comparator's domain can never bind a transfer.
    uint256 internal constant MAX_U64 = type(uint64).max;

    /// @dev 2**128 - 1, the domain of each address half decoded from the proof.
    uint256 internal constant MASK_128 = (1 << 128) - 1;

    // --------------------------------------------------------------------- //
    //                                 State                                 //
    // --------------------------------------------------------------------- //

    /// @notice Per-operator rolling daily-spend window. Mirrors Solana
    ///         `OperatorState` (minus the Solana-only pending_proof_hash, which
    ///         existed for the two-tx transfer-hook flow that EVM does not use).
    struct OperatorState {
        uint64 dailySpent;
        uint64 dayStartUnix;
        uint64 totalReleases;
    }

    mapping(address operator => OperatorState) private _state;

    /// @notice Funds an operator has locked in escrow, per ERC-20 token.
    mapping(address operator => mapping(address token => uint256 amount)) private _locked;

    /// @notice Consumed proof nullifiers (keccak256 of the full proof).
    mapping(bytes32 nullifier => bool) public consumedProof;

    /// @notice Per-operator EIP-712 authorization nonce (sequential).
    mapping(address operator => uint256 nonce) public nonces;

    /// @dev EIP-712 typed-data for a gasless, relayer-submitted release. This
    ///      is the EVM adaptation of the x402 payment header: the operator signs
    ///      the payment intent off-chain, a relayer submits it with the proof,
    ///      and the operator pays no gas.
    struct PaymentAuthorization {
        address operator;
        bytes32 policyId;
        address token;
        address recipient;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
    }

    bytes32 private constant PAYMENT_AUTHORIZATION_TYPEHASH = keccak256(
        "PaymentAuthorization(address operator,bytes32 policyId,address token,address recipient,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    // --------------------------------------------------------------------- //
    //                                Events                                 //
    // --------------------------------------------------------------------- //

    event Deposited(address indexed operator, address indexed token, uint256 amount, uint256 newLockedBalance);
    event Released(
        address indexed operator,
        address indexed token,
        address indexed recipient,
        uint256 amount,
        bytes32 policyId,
        bytes32 policyDataHash,
        uint64 dailySpentAfter,
        bytes32 nullifier
    );
    event Refunded(address indexed operator, address indexed token, uint256 amount, uint256 newLockedBalance);

    // --------------------------------------------------------------------- //
    //                                Errors                                 //
    // --------------------------------------------------------------------- //

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientLockedBalance(uint256 requested, uint256 available);
    error ProofVerificationFailed();
    error NotCompliant();
    error PolicyHashMismatch(bytes32 fromProof, bytes32 onChain);
    error DailySpentMismatch(uint256 fromProof, uint256 onChain);
    error TimestampOutOfRange(uint256 fromProof, uint256 blockTime);
    error StripeReceiptUnexpected(uint256 value);
    error RecipientMismatch(uint256 fromProof, address recipient);
    error TokenMismatch(uint256 fromProof, address token);
    error AmountMismatch(uint256 fromProof, uint256 amount);
    error FieldOverflow(uint256 index, uint256 value);
    error ProofAlreadyConsumed(bytes32 nullifier);
    error AuthorizationExpired(uint256 deadline, uint256 blockTime);
    error InvalidAuthorizationNonce(uint256 provided, uint256 expected);
    error InvalidSigner(address recovered, address operator);

    // --------------------------------------------------------------------- //
    //                              Constructor                              //
    // --------------------------------------------------------------------- //

    constructor(IGroth16Verifier verifier_, PolicyRegistry registry_)
        EIP712("ApertureComplianceEscrow", "1")
    {
        if (address(verifier_) == address(0) || address(registry_) == address(0)) revert ZeroAddress();
        verifier = verifier_;
        registry = registry_;
    }

    // --------------------------------------------------------------------- //
    //                              Lock / Refund                            //
    // --------------------------------------------------------------------- //

    /// @notice Lock `amount` of `token` into escrow under the caller's operator
    ///         balance. Requires a prior ERC-20 approval to this contract.
    function deposit(address token, uint256 amount) external nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // Credit the balance off the actually-received amount so fee-on-transfer
        // tokens cannot inflate locked accounting.
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - balanceBefore;

        uint256 newBalance = _locked[msg.sender][token] + received;
        _locked[msg.sender][token] = newBalance;

        emit Deposited(msg.sender, token, received, newBalance);
    }

    /// @notice Withdraw unspent locked funds back to the caller. This is the
    ///         "refund" leg of lock-release-refund; it needs no proof because
    ///         it only ever returns the operator's own escrowed balance.
    function refund(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 available = _locked[msg.sender][token];
        if (amount > available) revert InsufficientLockedBalance(amount, available);

        uint256 newBalance = available - amount;
        _locked[msg.sender][token] = newBalance;
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Refunded(msg.sender, token, amount, newBalance);
    }

    // --------------------------------------------------------------------- //
    //                            Release with proof                         //
    // --------------------------------------------------------------------- //

    /// @notice Release `amount` of `token` from the caller's locked balance to
    ///         `recipient`, gated by a Groth16 compliance proof. The caller is
    ///         the operator whose policy and daily-spend the proof commits to
    ///         and who pays the gas. For a gasless flow where a relayer pays the
    ///         gas, see `releaseWithProofSigned`.
    /// @param pA,pB,pC Groth16 proof points.
    /// @param pubSignals The circuit's 10 public outputs.
    /// @param policyId The operator's policy id whose hash the proof must match.
    /// @param token The ERC-20 being released.
    /// @param recipient The destination, byte-bound to the proof.
    /// @param amount The release amount, byte-bound to the proof.
    function releaseWithProof(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[10] calldata pubSignals,
        bytes32 policyId,
        address token,
        address recipient,
        uint256 amount
    ) external nonReentrant {
        // The operator pays their own gas: msg.sender is the operator.
        _release(msg.sender, pA, pB, pC, pubSignals, policyId, token, recipient, amount);
    }

    /// @notice Gasless, relayer-submitted release. The operator signs an
    ///         EIP-712 `PaymentAuthorization` off-chain (the EVM form of the
    ///         x402 payment header); anyone can submit it together with the
    ///         proof, and the operator's locked funds are released without the
    ///         operator paying gas. This is a relayer + EIP-712 meta-transaction
    ///         (`msg.sender` is the relayer), not an ERC-4337 paymaster. The
    ///         authorization is single-use via a sequential per-operator nonce
    ///         and bounded by a deadline.
    function releaseWithProofSigned(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[10] calldata pubSignals,
        PaymentAuthorization calldata auth,
        bytes calldata signature
    ) external nonReentrant {
        if (block.timestamp > auth.deadline) revert AuthorizationExpired(auth.deadline, block.timestamp);

        uint256 expected = nonces[auth.operator];
        if (auth.nonce != expected) revert InvalidAuthorizationNonce(auth.nonce, expected);

        bytes32 structHash = keccak256(
            abi.encode(
                PAYMENT_AUTHORIZATION_TYPEHASH,
                auth.operator,
                auth.policyId,
                auth.token,
                auth.recipient,
                auth.amount,
                auth.nonce,
                auth.deadline
            )
        );
        address signer = ECDSA.recover(_hashTypedDataV4(structHash), signature);
        if (signer != auth.operator) revert InvalidSigner(signer, auth.operator);

        // consume the nonce before effects (also guards reentrancy on the auth)
        nonces[auth.operator] = expected + 1;

        _release(auth.operator, pA, pB, pC, pubSignals, auth.policyId, auth.token, auth.recipient, auth.amount);
    }

    /// @notice The EIP-712 domain separator, exposed so off-chain signers can
    ///         build the typed data without guessing the chain id or address.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @dev Shared release path used by both the self-submitted and the
    ///      EIP-712-signed (relayer-submitted) entry points. `operator` is the
    ///      account whose policy, daily-spend and locked balance are used, and
    ///      whose funds are released, regardless of who pays the gas.
    function _release(
        address operator,
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[10] calldata pubSignals,
        bytes32 policyId,
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if (recipient == address(0) || token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // ---- 1. Groth16 cryptographic verification (real verifier) --------
        if (!verifier.verifyProof(pA, pB, pC, pubSignals)) revert ProofVerificationFailed();

        // ---- 2. is_compliant == 1 -----------------------------------------
        if (pubSignals[0] != 1) revert NotCompliant();

        // ---- 3. policy_data_hash matches the active on-chain policy --------
        // Reverts inside the registry if the policy is missing or inactive.
        (, bytes32 onChainPolicyHash,) = registry.getActivePolicyCommitments(operator, policyId);
        bytes32 proofPolicyHash = bytes32(pubSignals[1]);
        if (proofPolicyHash != onChainPolicyHash) revert PolicyHashMismatch(proofPolicyHash, onChainPolicyHash);

        // ---- 4. daily_spent_before matches effective on-chain spend --------
        OperatorState storage st = _state[operator];
        uint256 effectiveDaily = _isNewDay(st.dayStartUnix, block.timestamp) ? 0 : uint256(st.dailySpent);
        uint256 proofDaily = pubSignals[7];
        if (proofDaily > MAX_U64) revert FieldOverflow(7, proofDaily);
        if (proofDaily != effectiveDaily) revert DailySpentMismatch(proofDaily, effectiveDaily);

        // ---- 5. timestamp within tolerance --------------------------------
        uint256 proofTs = pubSignals[8];
        if (proofTs > MAX_U64) revert FieldOverflow(8, proofTs);
        uint256 drift = block.timestamp > proofTs ? block.timestamp - proofTs : proofTs - block.timestamp;
        if (drift > TIMESTAMP_TOLERANCE) revert TimestampOutOfRange(proofTs, block.timestamp);

        // ---- 6. no Stripe receipt on the pure-token flow ------------------
        if (pubSignals[9] != 0) revert StripeReceiptUnexpected(pubSignals[9]);

        // ---- 7. recipient / token / amount byte-binding -------------------
        uint256 proofRecipient = _decodeAddressField(2, pubSignals[2], pubSignals[3]);
        if (proofRecipient != uint256(uint160(recipient))) revert RecipientMismatch(proofRecipient, recipient);

        uint256 proofToken = _decodeAddressField(5, pubSignals[5], pubSignals[6]);
        if (proofToken != uint256(uint160(token))) revert TokenMismatch(proofToken, token);

        uint256 proofAmount = pubSignals[4];
        if (proofAmount > MAX_U64) revert FieldOverflow(4, proofAmount);
        if (proofAmount != amount) revert AmountMismatch(proofAmount, amount);

        // ---- 8. nullifier (defense in depth vs in-window replay) ----------
        bytes32 nullifier = keccak256(abi.encode(pA, pB, pC, pubSignals));
        if (consumedProof[nullifier]) revert ProofAlreadyConsumed(nullifier);
        consumedProof[nullifier] = true;

        // ---- 9. effects: roll the daily window, charge spend, debit lock --
        uint64 today = uint64(_dayStartFor(block.timestamp));
        if (st.dayStartUnix < today) {
            st.dayStartUnix = today;
            st.dailySpent = 0;
        }
        // amount <= MAX_U64 (bound to proofAmount above), so the cast is safe
        // and the checked add guards the daily counter.
        st.dailySpent += uint64(amount);
        st.totalReleases += 1;

        uint256 available = _locked[operator][token];
        if (amount > available) revert InsufficientLockedBalance(amount, available);
        _locked[operator][token] = available - amount;

        // ---- 10. interaction: release the ERC-20 to the recipient ---------
        IERC20(token).safeTransfer(recipient, amount);

        emit Released(operator, token, recipient, amount, policyId, proofPolicyHash, st.dailySpent, nullifier);
    }

    // --------------------------------------------------------------------- //
    //                                 Views                                 //
    // --------------------------------------------------------------------- //

    function lockedBalanceOf(address operator, address token) external view returns (uint256) {
        return _locked[operator][token];
    }

    function operatorState(address operator) external view returns (OperatorState memory) {
        return _state[operator];
    }

    /// @notice The operator's effective daily spend right now, accounting for
    ///         the UTC rollover. This is the value a fresh proof must commit to
    ///         as `daily_spent_before`.
    function effectiveDailySpent(address operator) external view returns (uint256) {
        OperatorState storage st = _state[operator];
        return _isNewDay(st.dayStartUnix, block.timestamp) ? 0 : uint256(st.dailySpent);
    }

    // --------------------------------------------------------------------- //
    //                          Internal: time + decode                      //
    // --------------------------------------------------------------------- //

    /// @dev Mirrors `OperatorState::day_start_for`.
    function _dayStartFor(uint256 ts) internal pure returns (uint256) {
        return ts - (ts % SECONDS_PER_DAY);
    }

    /// @dev Mirrors `OperatorState::is_new_day`.
    function _isNewDay(uint64 storedDayStart, uint256 nowTs) internal pure returns (bool) {
        return _dayStartFor(nowTs) > storedDayStart;
    }

    /// @dev Reconstruct a 160-bit EVM address from the circuit's high/low
    ///      128-bit field pair, mirroring Solana `read_high_low_pubkey`. Each
    ///      half must fit in 128 bits; the recombined value is
    ///      `high * 2**128 + low`, which for a valid address is < 2**160.
    function _decodeAddressField(uint256 firstIndex, uint256 high, uint256 low) internal pure returns (uint256) {
        if (high > MASK_128) revert FieldOverflow(firstIndex, high);
        if (low > MASK_128) revert FieldOverflow(firstIndex + 1, low);
        return (high << 128) | low;
    }
}
