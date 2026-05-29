/// Minimal ABIs (as const for viem type inference) covering the functions the
/// client uses. They mirror moca/contracts/src/*.sol.

export const policyRegistryAbi = [
  {
    type: "function",
    name: "initializeOperator",
    stateMutability: "nonpayable",
    inputs: [{ name: "name", type: "string" }],
    outputs: [],
  },
  {
    type: "function",
    name: "setMultisig",
    stateMutability: "nonpayable",
    inputs: [{ name: "multisig", type: "address" }],
    outputs: [],
  },
  {
    type: "function",
    name: "registerPolicy",
    stateMutability: "nonpayable",
    inputs: [
      { name: "operator", type: "address" },
      { name: "policyId", type: "bytes32" },
      { name: "merkleRoot", type: "bytes32" },
      { name: "policyDataHash", type: "bytes32" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "updatePolicy",
    stateMutability: "nonpayable",
    inputs: [
      { name: "operator", type: "address" },
      { name: "policyId", type: "bytes32" },
      { name: "newMerkleRoot", type: "bytes32" },
      { name: "newPolicyDataHash", type: "bytes32" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "deactivatePolicy",
    stateMutability: "nonpayable",
    inputs: [
      { name: "operator", type: "address" },
      { name: "policyId", type: "bytes32" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "operatorExists",
    stateMutability: "view",
    inputs: [{ name: "authority", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "policyExists",
    stateMutability: "view",
    inputs: [
      { name: "operator", type: "address" },
      { name: "policyId", type: "bytes32" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "getActivePolicyCommitments",
    stateMutability: "view",
    inputs: [
      { name: "operator", type: "address" },
      { name: "policyId", type: "bytes32" },
    ],
    outputs: [
      { name: "merkleRoot", type: "bytes32" },
      { name: "policyDataHash", type: "bytes32" },
      { name: "version", type: "uint32" },
    ],
  },
] as const;

export const complianceEscrowAbi = [
  {
    type: "function",
    name: "deposit",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "refund",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "releaseWithProof",
    stateMutability: "nonpayable",
    inputs: [
      { name: "pA", type: "uint256[2]" },
      { name: "pB", type: "uint256[2][2]" },
      { name: "pC", type: "uint256[2]" },
      { name: "pubSignals", type: "uint256[10]" },
      { name: "policyId", type: "bytes32" },
      { name: "token", type: "address" },
      { name: "recipient", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "releaseWithProofSigned",
    stateMutability: "nonpayable",
    inputs: [
      { name: "pA", type: "uint256[2]" },
      { name: "pB", type: "uint256[2][2]" },
      { name: "pC", type: "uint256[2]" },
      { name: "pubSignals", type: "uint256[10]" },
      {
        name: "auth",
        type: "tuple",
        components: [
          { name: "operator", type: "address" },
          { name: "policyId", type: "bytes32" },
          { name: "token", type: "address" },
          { name: "recipient", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" },
        ],
      },
      { name: "signature", type: "bytes" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "nonces",
    stateMutability: "view",
    inputs: [{ name: "operator", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "lockedBalanceOf",
    stateMutability: "view",
    inputs: [
      { name: "operator", type: "address" },
      { name: "token", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "effectiveDailySpent",
    stateMutability: "view",
    inputs: [{ name: "operator", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
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
  {
    type: "event",
    name: "Released",
    inputs: [
      { name: "operator", type: "address", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "recipient", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "policyId", type: "bytes32", indexed: false },
      { name: "policyDataHash", type: "bytes32", indexed: false },
      { name: "dailySpentAfter", type: "uint64", indexed: false },
      { name: "nullifier", type: "bytes32", indexed: false },
    ],
  },
] as const;

export const agentRegistryAbi = [
  {
    type: "function",
    name: "register",
    stateMutability: "nonpayable",
    inputs: [
      { name: "did", type: "string" },
      { name: "smartAccount", type: "address" },
      { name: "agentId", type: "string" },
      { name: "endpoint", type: "string" },
      { name: "metadataURI", type: "string" },
    ],
    outputs: [{ name: "hash", type: "bytes32" }],
  },
  {
    type: "function",
    name: "resolve",
    stateMutability: "view",
    inputs: [{ name: "did", type: "string" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "smartAccount", type: "address" },
          { name: "authority", type: "address" },
          { name: "did", type: "string" },
          { name: "agentId", type: "string" },
          { name: "endpoint", type: "string" },
          { name: "metadataURI", type: "string" },
          { name: "registeredAt", type: "uint64" },
          { name: "updatedAt", type: "uint64" },
          { name: "exists", type: "bool" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "resolveSmartAccount",
    stateMutability: "view",
    inputs: [{ name: "did", type: "string" }],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "didOf",
    stateMutability: "view",
    inputs: [{ name: "smartAccount", type: "address" }],
    outputs: [{ name: "", type: "string" }],
  },
  {
    type: "function",
    name: "exists",
    stateMutability: "view",
    inputs: [{ name: "did", type: "string" }],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

export const erc20Abi = [
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "mint",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
] as const;
