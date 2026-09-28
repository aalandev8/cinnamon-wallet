// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ECDSAValidator} from "../../src/modules/ECDSAValidator.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/IERC4337.sol";
import {
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK,
    MODULE_TYPE_HOOK,
    MODULE_TYPE_VALIDATOR,
    VALIDATION_FAILED,
    VALIDATION_SUCCESS
} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Test} from "forge-std/Test.sol";

contract ECDSAValidatorTest is Test {
    bytes32 constant USER_OP_HASH = keccak256("userOp");

    ECDSAValidator validator;
    address account;
    address owner;
    uint256 ownerKey;

    function setUp() public {
        validator = new ECDSAValidator();
        account = makeAddr("account");
        (owner, ownerKey) = makeAddrAndKey("owner");
    }

    function test_isModuleType_onlyValidator() public view {
        assertTrue(validator.isModuleType(MODULE_TYPE_VALIDATOR));
        assertFalse(validator.isModuleType(MODULE_TYPE_EXECUTOR));
        assertFalse(validator.isModuleType(MODULE_TYPE_FALLBACK));
        assertFalse(validator.isModuleType(MODULE_TYPE_HOOK));
    }

    function test_onInstall_setsOwnerForCallingAccount() public {
        vm.prank(account);
        validator.onInstall(abi.encode(owner));

        assertEq(validator.owner(account), owner);
    }

    function test_onInstall_revertsWhenOwnerIsZeroAddress() public {
        vm.prank(account);
        vm.expectRevert(ECDSAValidator.InvalidOwner.selector);
        validator.onInstall(abi.encode(address(0)));
    }

    function test_onInstall_revertsWhenAlreadyInstalled() public {
        vm.startPrank(account);
        validator.onInstall(abi.encode(owner));

        vm.expectRevert(abi.encodeWithSelector(ECDSAValidator.AlreadyInstalled.selector, account));
        validator.onInstall(abi.encode(owner));
    }

    function test_onUninstall_clearsOwner() public {
        vm.startPrank(account);
        validator.onInstall(abi.encode(owner));
        validator.onUninstall("");

        assertEq(validator.owner(account), address(0));
    }

    function test_validateUserOp_succeedsWithOwnerSignature() public {
        _install();

        vm.prank(account);
        assertEq(validator.validateUserOp(_userOpSignedBy(ownerKey), USER_OP_HASH), VALIDATION_SUCCESS);
    }

    function test_validateUserOp_failsWithOtherSigner(uint256 otherKey) public {
        otherKey = bound(otherKey, 1, SECP256K1_ORDER - 1);
        vm.assume(otherKey != ownerKey);
        _install();

        vm.prank(account);
        assertEq(validator.validateUserOp(_userOpSignedBy(otherKey), USER_OP_HASH), VALIDATION_FAILED);
    }

    function test_validateUserOp_failsWithMalformedSignature(bytes calldata signature) public {
        vm.assume(signature.length != 65);
        _install();
        PackedUserOperation memory userOp;
        userOp.signature = signature;

        vm.prank(account);
        assertEq(validator.validateUserOp(userOp, USER_OP_HASH), VALIDATION_FAILED);
    }

    function test_validateUserOp_isolatesOwnersPerAccount() public {
        _install();

        vm.prank(makeAddr("otherAccount"));
        assertEq(validator.validateUserOp(_userOpSignedBy(ownerKey), USER_OP_HASH), VALIDATION_FAILED);
    }

    function test_isValidSignatureWithSender_isNotSupported() public {
        _install();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, USER_OP_HASH);

        vm.prank(account);
        assertEq(
            validator.isValidSignatureWithSender(owner, USER_OP_HASH, abi.encodePacked(r, s, v)), bytes4(0xffffffff)
        );
    }

    function _install() private {
        vm.prank(account);
        validator.onInstall(abi.encode(owner));
    }

    function _userOpSignedBy(uint256 key) private pure returns (PackedUserOperation memory userOp) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, USER_OP_HASH);
        userOp.signature = abi.encodePacked(r, s, v);
    }
}
