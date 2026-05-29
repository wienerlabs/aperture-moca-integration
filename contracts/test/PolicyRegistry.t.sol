// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";

contract PolicyRegistryTest is Test {
    PolicyRegistry internal registry;

    address internal operator = makeAddr("operator");
    address internal multisig = makeAddr("multisig");
    address internal stranger = makeAddr("stranger");

    bytes32 internal constant POLICY_ID = bytes32(uint256(0xAA01));
    bytes32 internal constant MERKLE_ROOT = bytes32(uint256(0xBEEF));
    bytes32 internal constant POLICY_HASH = bytes32(uint256(0xCAFE));

    function setUp() public {
        registry = new PolicyRegistry();
    }

    // --------------------------- operator init --------------------------- //

    function test_InitializeOperator_setsFields() public {
        vm.prank(operator);
        registry.initializeOperator("Aperture Agent One");

        PolicyRegistry.Operator memory op = registry.getOperator(operator);
        assertEq(op.authority, operator);
        assertEq(op.multisig, address(0));
        assertEq(op.name, "Aperture Agent One");
        assertEq(op.policyCount, 0);
        assertEq(op.createdAt, uint64(block.timestamp));
        assertTrue(op.exists);
    }

    function test_InitializeOperator_revertsOnReinit() public {
        vm.startPrank(operator);
        registry.initializeOperator("First");
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.OperatorAlreadyExists.selector, operator));
        registry.initializeOperator("Second");
        vm.stopPrank();
    }

    function test_InitializeOperator_revertsOnEmptyName() public {
        vm.prank(operator);
        vm.expectRevert(PolicyRegistry.EmptyName.selector);
        registry.initializeOperator("");
    }

    function test_InitializeOperator_revertsOnNameTooLong() public {
        bytes memory longName = new bytes(65);
        for (uint256 i = 0; i < 65; i++) {
            longName[i] = "a";
        }
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.NameTooLong.selector, uint256(65)));
        registry.initializeOperator(string(longName));
    }

    function test_InitializeOperator_acceptsExactly64Bytes() public {
        bytes memory name64 = new bytes(64);
        for (uint256 i = 0; i < 64; i++) {
            name64[i] = "a";
        }
        vm.prank(operator);
        registry.initializeOperator(string(name64));
        assertTrue(registry.operatorExists(operator));
    }

    // --------------------------- register policy ------------------------- //

    function _initOperator() internal {
        vm.prank(operator);
        registry.initializeOperator("Operator");
    }

    function test_RegisterPolicy_byAuthority() public {
        _initOperator();
        vm.prank(operator);
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);

        PolicyRegistry.Policy memory p = registry.getPolicy(operator, POLICY_ID);
        assertEq(p.policyId, POLICY_ID);
        assertEq(p.merkleRoot, MERKLE_ROOT);
        assertEq(p.policyDataHash, POLICY_HASH);
        assertEq(p.version, 1);
        assertTrue(p.active);
        assertEq(p.createdAt, uint64(block.timestamp));
        assertEq(p.updatedAt, uint64(block.timestamp));
        assertTrue(p.exists);

        assertEq(registry.getOperator(operator).policyCount, 1);
    }

    function test_RegisterPolicy_revertsForUnknownOperator() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.OperatorNotFound.selector, operator));
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
    }

    function test_RegisterPolicy_revertsForStranger() public {
        _initOperator();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.Unauthorized.selector, stranger, operator));
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
    }

    function test_RegisterPolicy_revertsOnDuplicate() public {
        _initOperator();
        vm.startPrank(operator);
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.PolicyAlreadyExists.selector, operator, POLICY_ID));
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
        vm.stopPrank();
    }

    function test_RegisterPolicy_incrementsCountForMultiplePolicies() public {
        _initOperator();
        vm.startPrank(operator);
        registry.registerPolicy(operator, bytes32(uint256(1)), MERKLE_ROOT, POLICY_HASH);
        registry.registerPolicy(operator, bytes32(uint256(2)), MERKLE_ROOT, POLICY_HASH);
        registry.registerPolicy(operator, bytes32(uint256(3)), MERKLE_ROOT, POLICY_HASH);
        vm.stopPrank();
        assertEq(registry.getOperator(operator).policyCount, 3);
    }

    // --------------------------- multisig path --------------------------- //

    function test_Multisig_canManagePoliciesAfterBinding() public {
        _initOperator();
        vm.prank(operator);
        registry.setMultisig(multisig);
        assertEq(registry.getOperator(operator).multisig, multisig);

        // multisig registers on behalf of the operator
        vm.prank(multisig);
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
        assertTrue(registry.policyExists(operator, POLICY_ID));

        // and can update it
        vm.prank(multisig);
        registry.updatePolicy(operator, POLICY_ID, bytes32(uint256(0xD00D)), bytes32(uint256(0xF00D)));
        assertEq(registry.getPolicy(operator, POLICY_ID).version, 2);
    }

    function test_Multisig_strangerStillRejectedAfterBinding() public {
        _initOperator();
        vm.prank(operator);
        registry.setMultisig(multisig);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.Unauthorized.selector, stranger, operator));
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
    }

    function test_SetMultisig_revertsForUnknownOperator() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.OperatorNotFound.selector, operator));
        registry.setMultisig(multisig);
    }

    // ---------------------------- update policy -------------------------- //

    function test_UpdatePolicy_bumpsVersionAndCommitments() public {
        _initOperator();
        vm.startPrank(operator);
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);

        skip(10);
        bytes32 newRoot = bytes32(uint256(0x1111));
        bytes32 newHash = bytes32(uint256(0x2222));
        registry.updatePolicy(operator, POLICY_ID, newRoot, newHash);
        vm.stopPrank();

        PolicyRegistry.Policy memory p = registry.getPolicy(operator, POLICY_ID);
        assertEq(p.merkleRoot, newRoot);
        assertEq(p.policyDataHash, newHash);
        assertEq(p.version, 2);
        assertEq(p.updatedAt, uint64(block.timestamp));
    }

    function test_UpdatePolicy_revertsWhenMissing() public {
        _initOperator();
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.PolicyNotFound.selector, operator, POLICY_ID));
        registry.updatePolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
    }

    function test_UpdatePolicy_revertsWhenInactive() public {
        _initOperator();
        vm.startPrank(operator);
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
        registry.deactivatePolicy(operator, POLICY_ID);
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.PolicyInactive.selector, operator, POLICY_ID));
        registry.updatePolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
        vm.stopPrank();
    }

    // -------------------------- deactivate policy ------------------------ //

    function test_DeactivatePolicy_flipsActive() public {
        _initOperator();
        vm.startPrank(operator);
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
        registry.deactivatePolicy(operator, POLICY_ID);
        vm.stopPrank();
        assertFalse(registry.getPolicy(operator, POLICY_ID).active);
    }

    function test_GetActivePolicyCommitments_revertsWhenInactive() public {
        _initOperator();
        vm.startPrank(operator);
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
        registry.deactivatePolicy(operator, POLICY_ID);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(PolicyRegistry.PolicyInactive.selector, operator, POLICY_ID));
        registry.getActivePolicyCommitments(operator, POLICY_ID);
    }

    function test_GetActivePolicyCommitments_returnsValues() public {
        _initOperator();
        vm.prank(operator);
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
        (bytes32 root, bytes32 hash, uint32 version) = registry.getActivePolicyCommitments(operator, POLICY_ID);
        assertEq(root, MERKLE_ROOT);
        assertEq(hash, POLICY_HASH);
        assertEq(version, 1);
    }

    // ------------------------------- events ------------------------------ //

    function test_RegisterPolicy_emitsEvent() public {
        _initOperator();
        vm.expectEmit(true, true, false, true, address(registry));
        emit PolicyRegistry.PolicyRegistered(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH, 1, operator);
        vm.prank(operator);
        registry.registerPolicy(operator, POLICY_ID, MERKLE_ROOT, POLICY_HASH);
    }
}
