// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";

/// @notice Deploys the AgentRegistry (Faz 3) to Moca Chain testnet.
///   forge script script/DeployAgentRegistry.s.sol:DeployAgentRegistry \
///     --rpc-url https://rpc.testnet.mocachain.dev --broadcast
contract DeployAgentRegistry is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("MOCA_DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        AgentRegistry registry = new AgentRegistry();
        console2.log("AgentRegistry:", address(registry));
        vm.stopBroadcast();
    }
}
