// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ComplianceEscrow} from "../src/ComplianceEscrow.sol";
import {Groth16Verifier} from "../src/Groth16Verifier.sol";
import {IGroth16Verifier} from "../src/IGroth16Verifier.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {TestERC20} from "./TestERC20.sol";

/// @notice End-to-end Faz 5 tests. Every proof here is REAL: the test shells
///         out via FFI to the unchanged payment.circom artifacts (payment.wasm
///         + payment.zkey) through moca/prover-ffi/prove.mjs, then verifies the
///         proof on-chain with the snarkjs-generated Groth16Verifier and
///         releases ERC-20 funds through ComplianceEscrow. No fixtures, no
///         stubbed verifier.
contract ComplianceEscrowTest is Test {
    ComplianceEscrow internal escrow;
    Groth16Verifier internal verifier;
    PolicyRegistry internal registry;
    TestERC20 internal token;

    address internal operator = makeAddr("operator");
    address internal recipient = makeAddr("recipient");

    bytes32 internal constant POLICY_ID = bytes32(uint256(0xA9E5));
    bytes32 internal constant MERKLE_ROOT = bytes32(uint256(0x1234));
    uint256 internal constant AMOUNT = 5_000_000; // 5 USDC at 6 decimals
    uint256 internal constant TS = 1_735_689_600; // 2025-01-01 00:00:00 UTC

    function setUp() public {
        verifier = new Groth16Verifier();
        registry = new PolicyRegistry();
        escrow = new ComplianceEscrow(IGroth16Verifier(address(verifier)), registry);
        token = new TestERC20("Aperture Test USD", "atUSD", 6);

        // Pin block time so the proof's timestamp signal stays inside tolerance.
        vm.warp(TS);

        vm.prank(operator);
        registry.initializeOperator("E2E Operator");

        // Fund and lock the operator's escrow balance.
        token.mint(operator, 100 * AMOUNT);
        vm.startPrank(operator);
        token.approve(address(escrow), type(uint256).max);
        escrow.deposit(address(token), 100 * AMOUNT);
        vm.stopPrank();
    }

    // ------------------------------ FFI prover --------------------------- //

    struct Proof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
        uint256[10] pub;
    }

    function _prove(address to, address tkn, uint256 amount, uint256 ts, uint256 dailyBefore)
        internal
        returns (Proof memory p)
    {
        string[] memory cmd = new string[](7);
        cmd[0] = "node";
        cmd[1] = "../prover-ffi/prove.mjs";
        cmd[2] = vm.toString(to);
        cmd[3] = vm.toString(tkn);
        cmd[4] = vm.toString(amount);
        cmd[5] = vm.toString(ts);
        cmd[6] = vm.toString(dailyBefore);
        bytes memory out = vm.ffi(cmd);
        (p.a, p.b, p.c, p.pub) = abi.decode(out, (uint256[2], uint256[2][2], uint256[2], uint256[10]));
    }

    function _registerPolicyFromProof(Proof memory p) internal {
        vm.prank(operator);
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, bytes32(p.pub[1]));
    }

    // ------------------------------ happy path --------------------------- //

    function test_ReleaseWithRealProof() public {
        Proof memory p = _prove(recipient, address(token), AMOUNT, TS, 0);
        _registerPolicyFromProof(p);

        assertEq(token.balanceOf(recipient), 0);

        vm.prank(operator);
        escrow.releaseWithProof(p.a, p.b, p.c, p.pub, POLICY_ID, address(token), recipient, AMOUNT);

        assertEq(token.balanceOf(recipient), AMOUNT, "recipient received funds");
        assertEq(escrow.lockedBalanceOf(operator, address(token)), 100 * AMOUNT - AMOUNT, "locked debited");
        assertEq(escrow.effectiveDailySpent(operator), AMOUNT, "daily spend charged");
        ComplianceEscrow.OperatorState memory st = escrow.operatorState(operator);
        assertEq(st.totalReleases, 1);
    }

    function test_SecondPaymentCarriesDailySpend() public {
        // First payment with daily_spent_before = 0.
        Proof memory p1 = _prove(recipient, address(token), AMOUNT, TS, 0);
        _registerPolicyFromProof(p1);
        vm.prank(operator);
        escrow.releaseWithProof(p1.a, p1.b, p1.c, p1.pub, POLICY_ID, address(token), recipient, AMOUNT);

        // Second payment must commit daily_spent_before = AMOUNT (the new
        // effective spend) or the escrow rejects it. Same UTC day (no warp).
        Proof memory p2 = _prove(recipient, address(token), AMOUNT, TS, AMOUNT);
        vm.prank(operator);
        escrow.releaseWithProof(p2.a, p2.b, p2.c, p2.pub, POLICY_ID, address(token), recipient, AMOUNT);

        assertEq(token.balanceOf(recipient), 2 * AMOUNT);
        assertEq(escrow.effectiveDailySpent(operator), 2 * AMOUNT);
    }

    function test_DailyResetsOnNewUtcDay() public {
        Proof memory p1 = _prove(recipient, address(token), AMOUNT, TS, 0);
        _registerPolicyFromProof(p1);
        vm.prank(operator);
        escrow.releaseWithProof(p1.a, p1.b, p1.c, p1.pub, POLICY_ID, address(token), recipient, AMOUNT);
        assertEq(escrow.effectiveDailySpent(operator), AMOUNT);

        // Cross into the next UTC day: effective spend resets to 0.
        uint256 nextDay = TS + 86_400;
        vm.warp(nextDay);
        assertEq(escrow.effectiveDailySpent(operator), 0, "rolled over");

        Proof memory p2 = _prove(recipient, address(token), AMOUNT, nextDay, 0);
        vm.prank(operator);
        escrow.releaseWithProof(p2.a, p2.b, p2.c, p2.pub, POLICY_ID, address(token), recipient, AMOUNT);
        assertEq(escrow.effectiveDailySpent(operator), AMOUNT);
    }

    // ------------------------------ negative ----------------------------- //

    function test_ReplayRejected() public {
        Proof memory p = _prove(recipient, address(token), AMOUNT, TS, 0);
        _registerPolicyFromProof(p);
        vm.startPrank(operator);
        escrow.releaseWithProof(p.a, p.b, p.c, p.pub, POLICY_ID, address(token), recipient, AMOUNT);

        // Replaying the exact same proof is rejected. The first gate that
        // catches it is the daily-spend binding (the proof committed
        // daily_spent_before = 0, but after the first release the operator's
        // effective spend is AMOUNT), exactly the primary replay defense the
        // Solana handler relied on. The keccak nullifier is a secondary
        // backstop behind this check.
        vm.expectRevert(abi.encodeWithSelector(ComplianceEscrow.DailySpentMismatch.selector, 0, AMOUNT));
        escrow.releaseWithProof(p.a, p.b, p.c, p.pub, POLICY_ID, address(token), recipient, AMOUNT);
        vm.stopPrank();
    }

    function test_WrongRecipientRejected() public {
        // Proof is bound to `recipient`; try to release to a different address.
        Proof memory p = _prove(recipient, address(token), AMOUNT, TS, 0);
        _registerPolicyFromProof(p);
        address attacker = makeAddr("attacker");

        uint256 proofRecipient = (p.pub[2] << 128) | p.pub[3];
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceEscrow.RecipientMismatch.selector, proofRecipient, attacker)
        );
        escrow.releaseWithProof(p.a, p.b, p.c, p.pub, POLICY_ID, address(token), attacker, AMOUNT);
    }

    function test_WrongAmountRejected() public {
        Proof memory p = _prove(recipient, address(token), AMOUNT, TS, 0);
        _registerPolicyFromProof(p);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceEscrow.AmountMismatch.selector, AMOUNT, AMOUNT + 1)
        );
        escrow.releaseWithProof(p.a, p.b, p.c, p.pub, POLICY_ID, address(token), recipient, AMOUNT + 1);
    }

    function test_TamperedProofRejected() public {
        Proof memory p = _prove(recipient, address(token), AMOUNT, TS, 0);
        _registerPolicyFromProof(p);
        // Flip the first proof point: cryptographic verification must fail.
        p.a[0] = p.a[0] ^ 1;
        vm.prank(operator);
        vm.expectRevert(ComplianceEscrow.ProofVerificationFailed.selector);
        escrow.releaseWithProof(p.a, p.b, p.c, p.pub, POLICY_ID, address(token), recipient, AMOUNT);
    }

    function test_UnregisteredPolicyRejected() public {
        Proof memory p = _prove(recipient, address(token), AMOUNT, TS, 0);
        // Do NOT register the policy; the registry view must revert.
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.PolicyNotFound.selector, operator, POLICY_ID));
        escrow.releaseWithProof(p.a, p.b, p.c, p.pub, POLICY_ID, address(token), recipient, AMOUNT);
    }

    function test_StaleTimestampRejected() public {
        Proof memory p = _prove(recipient, address(token), AMOUNT, TS, 0);
        _registerPolicyFromProof(p);
        // Move well beyond the 60s tolerance.
        vm.warp(TS + 120);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceEscrow.TimestampOutOfRange.selector, TS, TS + 120)
        );
        escrow.releaseWithProof(p.a, p.b, p.c, p.pub, POLICY_ID, address(token), recipient, AMOUNT);
    }

    // ------------------- gasless EIP-712 signed release ------------------ //

    bytes32 internal constant AUTH_TYPEHASH = keccak256(
        "PaymentAuthorization(address operator,bytes32 policyId,address token,address recipient,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    function _setupKeyedOperator(string memory label) internal returns (address op, uint256 pk) {
        (op, pk) = makeAddrAndKey(label);
        vm.prank(op);
        registry.initializeOperator(label);
        token.mint(op, 100 * AMOUNT);
        vm.startPrank(op);
        token.approve(address(escrow), type(uint256).max);
        escrow.deposit(address(token), 100 * AMOUNT);
        vm.stopPrank();
    }

    function _signAuth(uint256 pk, ComplianceEscrow.PaymentAuthorization memory auth)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                AUTH_TYPEHASH, auth.operator, auth.policyId, auth.token, auth.recipient, auth.amount, auth.nonce, auth.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", escrow.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_GaslessSignedRelease() public {
        (address op, uint256 pk) = _setupKeyedOperator("SignedOperator");
        address relayer = makeAddr("relayer");

        Proof memory p = _prove(recipient, address(token), AMOUNT, TS, 0);
        vm.prank(op);
        registry.registerPolicy(op, POLICY_ID, MERKLE_ROOT, bytes32(p.pub[1]));

        ComplianceEscrow.PaymentAuthorization memory auth = ComplianceEscrow.PaymentAuthorization({
            operator: op,
            policyId: POLICY_ID,
            token: address(token),
            recipient: recipient,
            amount: AMOUNT,
            nonce: 0,
            deadline: TS + 3600
        });
        bytes memory sig = _signAuth(pk, auth);

        // A relayer (not the operator) submits and pays the gas.
        vm.prank(relayer);
        escrow.releaseWithProofSigned(p.a, p.b, p.c, p.pub, auth, sig);

        assertEq(token.balanceOf(recipient), AMOUNT, "recipient paid");
        assertEq(escrow.lockedBalanceOf(op, address(token)), 100 * AMOUNT - AMOUNT, "operator lock debited");
        assertEq(escrow.effectiveDailySpent(op), AMOUNT);
        assertEq(escrow.nonces(op), 1, "nonce consumed");

        // Replaying the same authorization fails on the nonce.
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(ComplianceEscrow.InvalidAuthorizationNonce.selector, 0, 1));
        escrow.releaseWithProofSigned(p.a, p.b, p.c, p.pub, auth, sig);
    }

    function test_SignedWrongSignerRejected() public {
        (address op,) = _setupKeyedOperator("SignedOperator2");
        (, uint256 attackerPk) = makeAddrAndKey("attacker");

        Proof memory p = _prove(recipient, address(token), AMOUNT, TS, 0);
        vm.prank(op);
        registry.registerPolicy(op, POLICY_ID, MERKLE_ROOT, bytes32(p.pub[1]));

        ComplianceEscrow.PaymentAuthorization memory auth = ComplianceEscrow.PaymentAuthorization({
            operator: op,
            policyId: POLICY_ID,
            token: address(token),
            recipient: recipient,
            amount: AMOUNT,
            nonce: 0,
            deadline: TS + 3600
        });
        // signed by the attacker, not the operator
        bytes memory sig = _signAuth(attackerPk, auth);

        vm.expectRevert();
        escrow.releaseWithProofSigned(p.a, p.b, p.c, p.pub, auth, sig);
    }

    function test_SignedExpiredRejected() public {
        (address op, uint256 pk) = _setupKeyedOperator("SignedOperator3");
        Proof memory p = _prove(recipient, address(token), AMOUNT, TS, 0);
        vm.prank(op);
        registry.registerPolicy(op, POLICY_ID, MERKLE_ROOT, bytes32(p.pub[1]));

        ComplianceEscrow.PaymentAuthorization memory auth = ComplianceEscrow.PaymentAuthorization({
            operator: op,
            policyId: POLICY_ID,
            token: address(token),
            recipient: recipient,
            amount: AMOUNT,
            nonce: 0,
            deadline: TS - 1 // already expired
        });
        bytes memory sig = _signAuth(pk, auth);

        vm.expectRevert(abi.encodeWithSelector(ComplianceEscrow.AuthorizationExpired.selector, TS - 1, TS));
        escrow.releaseWithProofSigned(p.a, p.b, p.c, p.pub, auth, sig);
    }

    // ------------------------------- refund ------------------------------ //

    function test_RefundReturnsUnspentLock() public {
        uint256 before = token.balanceOf(operator);
        vm.prank(operator);
        escrow.refund(address(token), 10 * AMOUNT);
        assertEq(token.balanceOf(operator), before + 10 * AMOUNT);
        assertEq(escrow.lockedBalanceOf(operator, address(token)), 100 * AMOUNT - 10 * AMOUNT);
    }
}
