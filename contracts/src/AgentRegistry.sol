// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title AgentRegistry
/// @notice On-chain agent identity registry for Moca Chain. An agent DID maps
///         to an EVM smart-account address, alongside its service endpoint and
///         metadata, and resolution runs over the Moca RPC. This mirrors the
///         agent-identity resolution Aperture used on Solana (where a DID
///         resolved to a wallet pubkey), now native to Moca as a contract.
///
/// @dev DID strings are keyed by their keccak256 hash (Solidity cannot use a
///      string as a mapping key directly while still exposing the original),
///      and the original string is stored for retrieval. A reverse index maps
///      a smart-account address back to its DID hash so callers can go from an
///      on-chain address (for example the operator behind a ComplianceEscrow
///      payment) to its agent identity.
contract AgentRegistry {
    struct Agent {
        address smartAccount; // the agent's EVM smart-account (resolution target)
        address authority; // the address that controls this record
        string did;
        string agentId;
        string endpoint;
        string metadataURI;
        uint64 registeredAt;
        uint64 updatedAt;
        bool exists;
    }

    mapping(bytes32 didHash => Agent) private _agents;
    mapping(address smartAccount => bytes32 didHash) private _didHashOf;

    event AgentRegistered(
        bytes32 indexed didHash,
        string did,
        address indexed smartAccount,
        address indexed authority,
        string agentId,
        string endpoint
    );
    event AgentUpdated(bytes32 indexed didHash, string endpoint, string metadataURI);
    event SmartAccountChanged(bytes32 indexed didHash, address indexed oldAccount, address indexed newAccount);

    error EmptyDid();
    error ZeroSmartAccount();
    error AgentAlreadyExists(bytes32 didHash);
    error AgentNotFound(bytes32 didHash);
    error SmartAccountAlreadyBound(address smartAccount);
    error Unauthorized(address caller, address authority);

    /// @notice keccak256 of the DID string, used as the storage key.
    function didHash(string calldata did) public pure returns (bytes32) {
        return keccak256(bytes(did));
    }

    /// @notice Register an agent: bind a DID to an EVM smart-account.
    function register(
        string calldata did,
        address smartAccount,
        string calldata agentId,
        string calldata endpoint,
        string calldata metadataURI
    ) external returns (bytes32 hash) {
        if (bytes(did).length == 0) revert EmptyDid();
        if (smartAccount == address(0)) revert ZeroSmartAccount();

        hash = keccak256(bytes(did));
        if (_agents[hash].exists) revert AgentAlreadyExists(hash);
        if (_didHashOf[smartAccount] != bytes32(0)) revert SmartAccountAlreadyBound(smartAccount);

        uint64 nowTs = uint64(block.timestamp);
        _agents[hash] = Agent({
            smartAccount: smartAccount,
            authority: msg.sender,
            did: did,
            agentId: agentId,
            endpoint: endpoint,
            metadataURI: metadataURI,
            registeredAt: nowTs,
            updatedAt: nowTs,
            exists: true
        });
        _didHashOf[smartAccount] = hash;

        emit AgentRegistered(hash, did, smartAccount, msg.sender, agentId, endpoint);
    }

    /// @notice Update mutable fields (endpoint, metadata). Authority only.
    function update(string calldata did, string calldata endpoint, string calldata metadataURI) external {
        bytes32 hash = keccak256(bytes(did));
        Agent storage agent = _agents[hash];
        if (!agent.exists) revert AgentNotFound(hash);
        if (msg.sender != agent.authority) revert Unauthorized(msg.sender, agent.authority);

        agent.endpoint = endpoint;
        agent.metadataURI = metadataURI;
        agent.updatedAt = uint64(block.timestamp);

        emit AgentUpdated(hash, endpoint, metadataURI);
    }

    /// @notice Rebind the DID to a new smart-account. Authority only.
    function setSmartAccount(string calldata did, address newSmartAccount) external {
        if (newSmartAccount == address(0)) revert ZeroSmartAccount();
        bytes32 hash = keccak256(bytes(did));
        Agent storage agent = _agents[hash];
        if (!agent.exists) revert AgentNotFound(hash);
        if (msg.sender != agent.authority) revert Unauthorized(msg.sender, agent.authority);
        if (_didHashOf[newSmartAccount] != bytes32(0)) revert SmartAccountAlreadyBound(newSmartAccount);

        address old = agent.smartAccount;
        delete _didHashOf[old];
        agent.smartAccount = newSmartAccount;
        agent.updatedAt = uint64(block.timestamp);
        _didHashOf[newSmartAccount] = hash;

        emit SmartAccountChanged(hash, old, newSmartAccount);
    }

    // ----------------------------- resolution ---------------------------- //

    /// @notice Resolve a DID string to its full agent record.
    function resolve(string calldata did) external view returns (Agent memory) {
        bytes32 hash = keccak256(bytes(did));
        Agent memory agent = _agents[hash];
        if (!agent.exists) revert AgentNotFound(hash);
        return agent;
    }

    /// @notice Resolve a DID directly to the EVM smart-account it maps to.
    function resolveSmartAccount(string calldata did) external view returns (address) {
        bytes32 hash = keccak256(bytes(did));
        Agent memory agent = _agents[hash];
        if (!agent.exists) revert AgentNotFound(hash);
        return agent.smartAccount;
    }

    /// @notice Reverse resolution: the DID string bound to a smart-account.
    function didOf(address smartAccount) external view returns (string memory) {
        bytes32 hash = _didHashOf[smartAccount];
        if (hash == bytes32(0)) revert AgentNotFound(hash);
        return _agents[hash].did;
    }

    function exists(string calldata did) external view returns (bool) {
        return _agents[keccak256(bytes(did))].exists;
    }
}
