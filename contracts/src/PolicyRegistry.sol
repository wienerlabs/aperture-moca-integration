// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title PolicyRegistry
/// @notice EVM port of Aperture's Solana `policy-registry` Anchor program for
///         Moca Chain. An operator (an AI-agent runner) registers compliance
///         policies; each policy commits to a Merkle root and a Poseidon
///         `policyDataHash`. The off-chain prover and the on-chain
///         `ComplianceEscrow` cross-check a payment proof's `policy_data_hash`
///         public signal against the value stored here, exactly as the Solana
///         verifier did against the `PolicyAccount` PDA.
///
/// @dev Mapping of Solana concepts to EVM:
///      - `OperatorAccount` PDA (seeds ["operator", authority]) becomes
///        `operators[authority]`, so there is one operator record per address.
///      - `PolicyAccount` PDA (seeds ["policy", operator, policy_id]) becomes
///        `policies[operator][policyId]`.
///      - The Anchor `has_one = authority` signer check becomes an
///        `msg.sender` authorization check. The Squads multisig variants
///        (`set_multisig` / `register_policy_multisig`) map to an optional
///        `multisig` co-authority address that may manage the operator's
///        policies alongside the authority.
contract PolicyRegistry {
    // --------------------------------------------------------------------- //
    //                                Types                                  //
    // --------------------------------------------------------------------- //

    /// @dev Mirrors Solana `OperatorAccount`. `authority` is the map key, kept
    ///      in the struct for parity and event clarity.
    struct Operator {
        address authority;
        address multisig; // address(0) when no multisig is bound
        string name;
        uint32 policyCount;
        uint64 createdAt;
        bool exists;
    }

    /// @dev Mirrors Solana `PolicyAccount`. `policyId`, `merkleRoot` and
    ///      `policyDataHash` are 32-byte values on both chains.
    struct Policy {
        bytes32 policyId;
        bytes32 merkleRoot;
        bytes32 policyDataHash;
        uint32 version;
        bool active;
        uint64 createdAt;
        uint64 updatedAt;
        bool exists;
    }

    // --------------------------------------------------------------------- //
    //                                Storage                                //
    // --------------------------------------------------------------------- //

    /// @notice One operator record per authority address.
    mapping(address authority => Operator) private _operators;

    /// @notice Policies owned by an operator, keyed by the operator's
    ///         authority address and the 32-byte policy id.
    mapping(address authority => mapping(bytes32 policyId => Policy)) private _policies;

    /// @dev Matches the `#[max_len(64)]` cap on the Solana operator name.
    uint256 public constant MAX_NAME_BYTES = 64;

    // --------------------------------------------------------------------- //
    //                                Events                                 //
    // --------------------------------------------------------------------- //

    event OperatorInitialized(address indexed authority, string name, uint64 createdAt);
    event MultisigSet(address indexed authority, address indexed multisig);
    event PolicyRegistered(
        address indexed operator,
        bytes32 indexed policyId,
        bytes32 merkleRoot,
        bytes32 policyDataHash,
        uint32 version,
        address registeredBy
    );
    event PolicyUpdated(
        address indexed operator,
        bytes32 indexed policyId,
        bytes32 newMerkleRoot,
        bytes32 newPolicyDataHash,
        uint32 version,
        address updatedBy
    );
    event PolicyDeactivated(address indexed operator, bytes32 indexed policyId, uint32 version, address deactivatedBy);

    // --------------------------------------------------------------------- //
    //                                Errors                                 //
    // --------------------------------------------------------------------- //

    error OperatorAlreadyExists(address authority);
    error OperatorNotFound(address authority);
    error PolicyAlreadyExists(address operator, bytes32 policyId);
    error PolicyNotFound(address operator, bytes32 policyId);
    error PolicyInactive(address operator, bytes32 policyId);
    error Unauthorized(address caller, address operator);
    error EmptyName();
    error NameTooLong(uint256 length);

    // --------------------------------------------------------------------- //
    //                              Modifiers                                //
    // --------------------------------------------------------------------- //

    /// @dev Authorizes the operator's `authority` or its bound `multisig`.
    ///      This is the EVM equivalent of the Anchor `has_one = authority`
    ///      signer constraint plus the Squads multisig co-signer path.
    modifier onlyOperatorManager(address operator) {
        Operator storage op = _operators[operator];
        if (!op.exists) revert OperatorNotFound(operator);
        if (msg.sender != operator && msg.sender != op.multisig) {
            revert Unauthorized(msg.sender, operator);
        }
        _;
    }

    // --------------------------------------------------------------------- //
    //                           Operator lifecycle                          //
    // --------------------------------------------------------------------- //

    /// @notice Initialize the caller as an operator. One record per address;
    ///         re-initialization reverts, matching Anchor's `init` constraint.
    /// @param name Human-readable operator name (max 64 bytes).
    function initializeOperator(string calldata name) external {
        bytes memory nameBytes = bytes(name);
        if (nameBytes.length == 0) revert EmptyName();
        if (nameBytes.length > MAX_NAME_BYTES) revert NameTooLong(nameBytes.length);

        Operator storage op = _operators[msg.sender];
        if (op.exists) revert OperatorAlreadyExists(msg.sender);

        op.authority = msg.sender;
        op.multisig = address(0);
        op.name = name;
        op.policyCount = 0;
        op.createdAt = uint64(block.timestamp);
        op.exists = true;

        emit OperatorInitialized(msg.sender, name, op.createdAt);
    }

    /// @notice Bind (or clear, by passing address(0)) a multisig co-authority
    ///         for the caller's operator record. Mirrors `set_multisig`.
    function setMultisig(address multisig) external {
        Operator storage op = _operators[msg.sender];
        if (!op.exists) revert OperatorNotFound(msg.sender);
        op.multisig = multisig;
        emit MultisigSet(msg.sender, multisig);
    }

    // --------------------------------------------------------------------- //
    //                            Policy lifecycle                           //
    // --------------------------------------------------------------------- //

    /// @notice Register a new policy for `operator`. Reverts if a policy with
    ///         the same id already exists (Anchor `init` semantics). Callable
    ///         by the operator authority or its bound multisig.
    function registerPolicy(
        address operator,
        bytes32 policyId,
        bytes32 merkleRoot,
        bytes32 policyDataHash
    ) external onlyOperatorManager(operator) {
        Policy storage policy = _policies[operator][policyId];
        if (policy.exists) revert PolicyAlreadyExists(operator, policyId);

        uint64 nowTs = uint64(block.timestamp);
        policy.policyId = policyId;
        policy.merkleRoot = merkleRoot;
        policy.policyDataHash = policyDataHash;
        policy.version = 1;
        policy.active = true;
        policy.createdAt = nowTs;
        policy.updatedAt = nowTs;
        policy.exists = true;

        // checked arithmetic (Solidity 0.8) mirrors Anchor's checked_add.
        _operators[operator].policyCount += 1;

        emit PolicyRegistered(operator, policyId, merkleRoot, policyDataHash, policy.version, msg.sender);
    }

    /// @notice Update an existing, active policy's commitments and bump its
    ///         version. Mirrors `update_policy` (requires `active`).
    function updatePolicy(
        address operator,
        bytes32 policyId,
        bytes32 newMerkleRoot,
        bytes32 newPolicyDataHash
    ) external onlyOperatorManager(operator) {
        Policy storage policy = _policies[operator][policyId];
        if (!policy.exists) revert PolicyNotFound(operator, policyId);
        if (!policy.active) revert PolicyInactive(operator, policyId);

        policy.merkleRoot = newMerkleRoot;
        policy.policyDataHash = newPolicyDataHash;
        policy.version += 1;
        policy.updatedAt = uint64(block.timestamp);

        emit PolicyUpdated(operator, policyId, newMerkleRoot, newPolicyDataHash, policy.version, msg.sender);
    }

    /// @notice Deactivate a policy. Mirrors `deactivate_policy`. Idempotent on
    ///         an already-inactive policy is disallowed only by the existence
    ///         check; the Solana version also simply flips the flag.
    function deactivatePolicy(address operator, bytes32 policyId) external onlyOperatorManager(operator) {
        Policy storage policy = _policies[operator][policyId];
        if (!policy.exists) revert PolicyNotFound(operator, policyId);

        policy.active = false;
        policy.updatedAt = uint64(block.timestamp);

        emit PolicyDeactivated(operator, policyId, policy.version, msg.sender);
    }

    // --------------------------------------------------------------------- //
    //                                 Views                                 //
    // --------------------------------------------------------------------- //

    function getOperator(address authority) external view returns (Operator memory) {
        Operator memory op = _operators[authority];
        if (!op.exists) revert OperatorNotFound(authority);
        return op;
    }

    function operatorExists(address authority) external view returns (bool) {
        return _operators[authority].exists;
    }

    function getPolicy(address operator, bytes32 policyId) external view returns (Policy memory) {
        Policy memory policy = _policies[operator][policyId];
        if (!policy.exists) revert PolicyNotFound(operator, policyId);
        return policy;
    }

    function policyExists(address operator, bytes32 policyId) external view returns (bool) {
        return _policies[operator][policyId].exists;
    }

    /// @notice Read just the policy commitments the escrow verifier needs.
    ///         Reverts if the policy is missing or inactive so callers cannot
    ///         gate a payment on a withdrawn policy.
    function getActivePolicyCommitments(address operator, bytes32 policyId)
        external
        view
        returns (bytes32 merkleRoot, bytes32 policyDataHash, uint32 version)
    {
        Policy storage policy = _policies[operator][policyId];
        if (!policy.exists) revert PolicyNotFound(operator, policyId);
        if (!policy.active) revert PolicyInactive(operator, policyId);
        return (policy.merkleRoot, policy.policyDataHash, policy.version);
    }
}
