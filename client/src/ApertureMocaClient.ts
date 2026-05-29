import {
  createPublicClient,
  createWalletClient,
  http,
  type Account,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

import { mocaTestnet } from "./chain.js";
import { agentRegistryAbi, complianceEscrowAbi, erc20Abi, policyRegistryAbi } from "./abis.js";
import { generatePaymentProof, type PaymentProof } from "./proof.js";

export interface ContractAddresses {
  policyRegistry: Address;
  complianceEscrow: Address;
  /// Optional: required only for the DID resolver (Faz 3) methods.
  agentRegistry?: Address;
}

export interface ClientConfig {
  rpcUrl?: string;
  privateKey?: Hex;
  addresses: ContractAddresses;
}

export interface PayParams {
  policyId: Hex;
  token: Address;
  recipient: Address;
  amount: bigint;
  /// Override the proof timestamp. Defaults to the latest block timestamp so
  /// the proof always lands inside the escrow's 60s tolerance.
  timestamp?: bigint;
}

/// High-level client for the Aperture-on-Moca contract stack. Read methods need
/// only an RPC; write methods need a private key.
export class ApertureMocaClient {
  readonly publicClient: PublicClient;
  readonly walletClient?: WalletClient;
  readonly account?: Account;
  readonly addresses: ContractAddresses;

  constructor(config: ClientConfig) {
    const transport = http(config.rpcUrl ?? mocaTestnet.rpcUrls.default.http[0]);
    this.publicClient = createPublicClient({ chain: mocaTestnet, transport });
    this.addresses = config.addresses;

    if (config.privateKey) {
      this.account = privateKeyToAccount(config.privateKey);
      this.walletClient = createWalletClient({
        account: this.account,
        chain: mocaTestnet,
        transport,
      });
    }
  }

  private requireWallet(): { wallet: WalletClient; account: Account } {
    if (!this.walletClient || !this.account) {
      throw new Error("a privateKey is required for write operations");
    }
    return { wallet: this.walletClient, account: this.account };
  }

  // --------------------------------------------------------------------- //
  //                          Operator + policy                            //
  // --------------------------------------------------------------------- //

  async operatorExists(authority: Address): Promise<boolean> {
    return this.publicClient.readContract({
      address: this.addresses.policyRegistry,
      abi: policyRegistryAbi,
      functionName: "operatorExists",
      args: [authority],
    });
  }

  async initializeOperator(name: string): Promise<Hex> {
    const { wallet, account } = this.requireWallet();
    return wallet.writeContract({
      address: this.addresses.policyRegistry,
      abi: policyRegistryAbi,
      functionName: "initializeOperator",
      args: [name],
      account,
      chain: mocaTestnet,
    });
  }

  async registerPolicy(
    operator: Address,
    policyId: Hex,
    merkleRoot: Hex,
    policyDataHash: Hex,
  ): Promise<Hex> {
    const { wallet, account } = this.requireWallet();
    return wallet.writeContract({
      address: this.addresses.policyRegistry,
      abi: policyRegistryAbi,
      functionName: "registerPolicy",
      args: [operator, policyId, merkleRoot, policyDataHash],
      account,
      chain: mocaTestnet,
    });
  }

  async getActivePolicyCommitments(operator: Address, policyId: Hex) {
    const [merkleRoot, policyDataHash, version] = await this.publicClient.readContract({
      address: this.addresses.policyRegistry,
      abi: policyRegistryAbi,
      functionName: "getActivePolicyCommitments",
      args: [operator, policyId],
    });
    return { merkleRoot, policyDataHash, version };
  }

  // --------------------------------------------------------------------- //
  //                          Escrow lock / refund                         //
  // --------------------------------------------------------------------- //

  async approve(token: Address, amount: bigint): Promise<Hex> {
    const { wallet, account } = this.requireWallet();
    return wallet.writeContract({
      address: token,
      abi: erc20Abi,
      functionName: "approve",
      args: [this.addresses.complianceEscrow, amount],
      account,
      chain: mocaTestnet,
    });
  }

  async deposit(token: Address, amount: bigint): Promise<Hex> {
    const { wallet, account } = this.requireWallet();
    return wallet.writeContract({
      address: this.addresses.complianceEscrow,
      abi: complianceEscrowAbi,
      functionName: "deposit",
      args: [token, amount],
      account,
      chain: mocaTestnet,
    });
  }

  async refund(token: Address, amount: bigint): Promise<Hex> {
    const { wallet, account } = this.requireWallet();
    return wallet.writeContract({
      address: this.addresses.complianceEscrow,
      abi: complianceEscrowAbi,
      functionName: "refund",
      args: [token, amount],
      account,
      chain: mocaTestnet,
    });
  }

  async lockedBalanceOf(operator: Address, token: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.addresses.complianceEscrow,
      abi: complianceEscrowAbi,
      functionName: "lockedBalanceOf",
      args: [operator, token],
    });
  }

  async effectiveDailySpent(operator: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.addresses.complianceEscrow,
      abi: complianceEscrowAbi,
      functionName: "effectiveDailySpent",
      args: [operator],
    });
  }

  // --------------------------------------------------------------------- //
  //                          ZK-gated release                             //
  // --------------------------------------------------------------------- //

  /// Generate a real compliance proof for the payment and release the funds
  /// from the caller's escrow balance. The proof timestamp defaults to the
  /// latest block time and the daily-spend commitment to the operator's
  /// current effective spend, so the escrow's checks line up automatically.
  async payWithProof(params: PayParams): Promise<{ txHash: Hex; proofTimestamp: bigint }> {
    const { wallet, account } = this.requireWallet();

    const timestamp =
      params.timestamp ?? (await this.publicClient.getBlock({ blockTag: "latest" })).timestamp;
    const dailyBefore = await this.effectiveDailySpent(account.address);

    const proof = await generatePaymentProof({
      recipient: params.recipient,
      token: params.token,
      amount: params.amount,
      timestamp,
      dailyBefore,
    });

    const txHash = await wallet.writeContract({
      address: this.addresses.complianceEscrow,
      abi: complianceEscrowAbi,
      functionName: "releaseWithProof",
      args: [
        proof.a,
        proof.b,
        proof.c,
        proof.pubSignals,
        params.policyId,
        params.token,
        params.recipient,
        params.amount,
      ],
      account,
      chain: mocaTestnet,
    });

    return { txHash, proofTimestamp: timestamp };
  }

  // --------------------------------------------------------------------- //
  //              Gasless EIP-712 release (Faz 5, x402 on EVM)              //
  // --------------------------------------------------------------------- //

  /// The operator's current EIP-712 authorization nonce.
  async nonceOf(operator: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.addresses.complianceEscrow,
      abi: complianceEscrowAbi,
      functionName: "nonces",
      args: [operator],
    });
  }

  /// Operator side: sign an EIP-712 PaymentAuthorization (no transaction, no
  /// gas). This is the EVM form of an x402 payment header.
  async signPaymentAuthorization(auth: {
    operator: Address;
    policyId: Hex;
    token: Address;
    recipient: Address;
    amount: bigint;
    nonce: bigint;
    deadline: bigint;
  }): Promise<Hex> {
    const { wallet, account } = this.requireWallet();
    return wallet.signTypedData({
      account,
      domain: {
        name: "ApertureComplianceEscrow",
        version: "1",
        chainId: mocaTestnet.id,
        verifyingContract: this.addresses.complianceEscrow,
      },
      types: {
        PaymentAuthorization: [
          { name: "operator", type: "address" },
          { name: "policyId", type: "bytes32" },
          { name: "token", type: "address" },
          { name: "recipient", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" },
        ],
      },
      primaryType: "PaymentAuthorization",
      message: auth,
    });
  }

  /// Relayer side: submit a signed authorization plus proof. The relayer pays
  /// the gas; the operator pays nothing for the payment itself.
  async submitSignedRelease(
    proof: { a: PaymentProof["a"]; b: PaymentProof["b"]; c: PaymentProof["c"]; pubSignals: PaymentProof["pubSignals"] },
    auth: {
      operator: Address;
      policyId: Hex;
      token: Address;
      recipient: Address;
      amount: bigint;
      nonce: bigint;
      deadline: bigint;
    },
    signature: Hex,
  ): Promise<Hex> {
    const { wallet, account } = this.requireWallet();
    return wallet.writeContract({
      address: this.addresses.complianceEscrow,
      abi: complianceEscrowAbi,
      functionName: "releaseWithProofSigned",
      args: [proof.a, proof.b, proof.c, proof.pubSignals, auth, signature],
      account,
      chain: mocaTestnet,
    });
  }

  // --------------------------------------------------------------------- //
  //                      DID resolver (Faz 3, Moca RPC)                    //
  // --------------------------------------------------------------------- //

  private requireAgentRegistry(): Address {
    if (!this.addresses.agentRegistry) {
      throw new Error("agentRegistry address is required for DID resolution");
    }
    return this.addresses.agentRegistry;
  }

  /// Register an agent DID -> EVM smart-account mapping on Moca.
  async registerAgent(params: {
    did: string;
    smartAccount: Address;
    agentId: string;
    endpoint: string;
    metadataURI: string;
  }): Promise<Hex> {
    const { wallet, account } = this.requireWallet();
    return wallet.writeContract({
      address: this.requireAgentRegistry(),
      abi: agentRegistryAbi,
      functionName: "register",
      args: [params.did, params.smartAccount, params.agentId, params.endpoint, params.metadataURI],
      account,
      chain: mocaTestnet,
    });
  }

  /// Resolve a DID to its full agent record over the Moca RPC.
  async resolveAgent(did: string) {
    return this.publicClient.readContract({
      address: this.requireAgentRegistry(),
      abi: agentRegistryAbi,
      functionName: "resolve",
      args: [did],
    });
  }

  /// Resolve a DID directly to the EVM smart-account it maps to.
  async resolveSmartAccount(did: string): Promise<Address> {
    return this.publicClient.readContract({
      address: this.requireAgentRegistry(),
      abi: agentRegistryAbi,
      functionName: "resolveSmartAccount",
      args: [did],
    });
  }

  /// Reverse resolution: the DID bound to a smart-account.
  async didOf(smartAccount: Address): Promise<string> {
    return this.publicClient.readContract({
      address: this.requireAgentRegistry(),
      abi: agentRegistryAbi,
      functionName: "didOf",
      args: [smartAccount],
    });
  }
}
