import { defineChain } from "viem";

/// Moca Chain testnet (Evmos-based, London opcode set with bn128 precompiles).
export const mocaTestnet = defineChain({
  id: 222888,
  name: "Moca Chain Testnet",
  nativeCurrency: { name: "Moca", symbol: "MOCA", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://rpc.testnet.mocachain.dev"] },
  },
  blockExplorers: {
    default: {
      name: "Moca Testnet Scan",
      url: "https://testnet-scan.mocachain.org",
    },
  },
  testnet: true,
});
