// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ComplianceEscrow} from "../src/ComplianceEscrow.sol";
import {IGroth16Verifier} from "../src/IGroth16Verifier.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";

/// @notice Deploys a fresh ComplianceEscrow wired to the ALREADY-deployed
///         verifier and registry, so existing operators/policies carry over.
///   Required env: MOCA_DEPLOYER_PRIVATE_KEY, MOCA_GROTH16_VERIFIER,
///   MOCA_POLICY_REGISTRY
contract DeployEscrowOnly is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("MOCA_DEPLOYER_PRIVATE_KEY");
        address verifier = vm.envAddress("MOCA_GROTH16_VERIFIER");
        address registry = vm.envAddress("MOCA_POLICY_REGISTRY");

        vm.startBroadcast(deployerKey);
        ComplianceEscrow escrow =
            new ComplianceEscrow(IGroth16Verifier(verifier), PolicyRegistry(registry));
        console2.log("ComplianceEscrow:", address(escrow));
        vm.stopBroadcast();
    }
}
