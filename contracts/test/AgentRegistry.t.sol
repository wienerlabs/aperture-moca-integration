// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";

contract AgentRegistryTest is Test {
    AgentRegistry internal registry;

    address internal authority = makeAddr("authority");
    address internal smartAccount = makeAddr("smartAccount");
    address internal other = makeAddr("other");

    string internal constant DID = "did:moca:aperture-agent-1";

    function setUp() public {
        registry = new AgentRegistry();
    }

    function test_RegisterAndResolve() public {
        vm.prank(authority);
        registry.register(DID, smartAccount, "agent-1", "https://agent.example/api", "ipfs://meta");

        AgentRegistry.Agent memory a = registry.resolve(DID);
        assertEq(a.smartAccount, smartAccount);
        assertEq(a.authority, authority);
        assertEq(a.did, DID);
        assertEq(a.agentId, "agent-1");
        assertEq(a.endpoint, "https://agent.example/api");
        assertTrue(a.exists);

        assertEq(registry.resolveSmartAccount(DID), smartAccount);
        assertEq(registry.didOf(smartAccount), DID);
        assertTrue(registry.exists(DID));
    }

    function test_RegisterRevertsOnEmptyDid() public {
        vm.prank(authority);
        vm.expectRevert(AgentRegistry.EmptyDid.selector);
        registry.register("", smartAccount, "a", "e", "m");
    }

    function test_RegisterRevertsOnZeroSmartAccount() public {
        vm.prank(authority);
        vm.expectRevert(AgentRegistry.ZeroSmartAccount.selector);
        registry.register(DID, address(0), "a", "e", "m");
    }

    function test_RegisterRevertsOnDuplicateDid() public {
        vm.startPrank(authority);
        registry.register(DID, smartAccount, "a", "e", "m");
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentAlreadyExists.selector, registry.didHash(DID)));
        registry.register(DID, other, "a", "e", "m");
        vm.stopPrank();
    }

    function test_RegisterRevertsWhenSmartAccountAlreadyBound() public {
        vm.startPrank(authority);
        registry.register(DID, smartAccount, "a", "e", "m");
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.SmartAccountAlreadyBound.selector, smartAccount));
        registry.register("did:moca:other", smartAccount, "a", "e", "m");
        vm.stopPrank();
    }

    function test_UpdateByAuthority() public {
        vm.startPrank(authority);
        registry.register(DID, smartAccount, "a", "e1", "m1");
        skip(5);
        registry.update(DID, "https://new.endpoint", "ipfs://new");
        vm.stopPrank();

        AgentRegistry.Agent memory a = registry.resolve(DID);
        assertEq(a.endpoint, "https://new.endpoint");
        assertEq(a.metadataURI, "ipfs://new");
        assertEq(a.updatedAt, uint64(block.timestamp));
    }

    function test_UpdateRevertsForNonAuthority() public {
        vm.prank(authority);
        registry.register(DID, smartAccount, "a", "e", "m");
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.Unauthorized.selector, other, authority));
        registry.update(DID, "x", "y");
    }

    function test_SetSmartAccountRebindsReverseIndex() public {
        address newAccount = makeAddr("newAccount");
        vm.startPrank(authority);
        registry.register(DID, smartAccount, "a", "e", "m");
        registry.setSmartAccount(DID, newAccount);
        vm.stopPrank();

        assertEq(registry.resolveSmartAccount(DID), newAccount);
        assertEq(registry.didOf(newAccount), DID);
        // old account no longer resolves
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentNotFound.selector, bytes32(0)));
        registry.didOf(smartAccount);
    }

    function test_ResolveRevertsForUnknownDid() public {
        bytes32 hash = registry.didHash("did:moca:nope");
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentNotFound.selector, hash));
        registry.resolve("did:moca:nope");
    }

    function test_RegisterEmitsEvent() public {
        bytes32 hash = registry.didHash(DID);
        vm.expectEmit(true, true, true, true, address(registry));
        emit AgentRegistry.AgentRegistered(hash, DID, smartAccount, authority, "agent-1", "https://e");
        vm.prank(authority);
        registry.register(DID, smartAccount, "agent-1", "https://e", "m");
    }
}
