// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Groth16Verifier} from "../src/Groth16Verifier.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {ComplianceEscrow} from "../src/ComplianceEscrow.sol";
import {IGroth16Verifier} from "../src/IGroth16Verifier.sol";
import {TestERC20} from "../test/TestERC20.sol";

/// @notice Deploys the Aperture-on-Moca contract stack to Moca Chain testnet.
///
/// Required env:
///   MOCA_DEPLOYER_PRIVATE_KEY  funded testnet key (hex, 0x-prefixed)
/// Optional env:
///   MOCA_DEPLOY_TEST_TOKEN     "true" to also deploy a test stablecoin
///
/// Run:
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url https://rpc.testnet.mocachain.dev \
///     --broadcast
///
/// Moca Chain testnet has no canonical USDC, so MOCA_DEPLOY_TEST_TOKEN lets the
/// deployer publish a real ERC-20 (OpenZeppelin) to use as the payment token.
/// This is a real on-chain token, not a behavioral mock.
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("MOCA_DEPLOYER_PRIVATE_KEY");
        bool deployTestToken = vm.envOr("MOCA_DEPLOY_TEST_TOKEN", false);

        vm.startBroadcast(deployerKey);

        Groth16Verifier verifier = new Groth16Verifier();
        PolicyRegistry registry = new PolicyRegistry();
        ComplianceEscrow escrow = new ComplianceEscrow(IGroth16Verifier(address(verifier)), registry);

        console2.log("Groth16Verifier:", address(verifier));
        console2.log("PolicyRegistry: ", address(registry));
        console2.log("ComplianceEscrow:", address(escrow));

        if (deployTestToken) {
            TestERC20 token = new TestERC20("Aperture Test USD", "atUSD", 6);
            console2.log("TestERC20 (atUSD):", address(token));
        }

        vm.stopBroadcast();
    }
}
