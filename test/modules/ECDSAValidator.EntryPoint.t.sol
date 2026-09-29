// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WalletCore} from "../../src/WalletCore.sol";
import {ECDSAValidator} from "../../src/modules/ECDSAValidator.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

contract ECDSAValidatorEntryPointTest is Test {
    EntryPoint entryPoint;
    WalletCore wallet;
    ECDSAValidator validator;
    uint256 ownerKey;
    address payable beneficiary;

    function setUp() public {
        entryPoint = new EntryPoint();
        validator = new ECDSAValidator();
        address owner;
        (owner, ownerKey) = makeAddrAndKey("owner");
        WalletCore implementation = new WalletCore(address(entryPoint));
        wallet = WalletCore(payable(Clones.clone(address(implementation))));
        wallet.initialize(address(validator), abi.encode(owner));
        vm.deal(address(wallet), 1 ether);
        beneficiary = payable(makeAddr("beneficiary"));
    }

    function test_handleOps_acceptsUserOpSignedByOwner() public {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _signedUserOp(ownerKey);

        entryPoint.handleOps(ops, beneficiary);

        assertEq(entryPoint.getNonce(address(wallet), 0), 1);
    }

    function test_handleOps_rejectsUserOpSignedByOtherKey() public {
        (, uint256 otherKey) = makeAddrAndKey("other");
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _signedUserOp(otherKey);

        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(ops, beneficiary);
    }

    function test_handleOps_rejectsSignatureOverTamperedUserOp() public {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _signedUserOp(ownerKey);
        ops[0].preVerificationGas += 1;

        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(ops, beneficiary);
    }

    function _signedUserOp(uint256 key) private view returns (PackedUserOperation memory op) {
        op.sender = address(wallet);
        op.nonce = entryPoint.getNonce(address(wallet), 0);
        op.accountGasLimits = bytes32(uint256(200_000) << 128 | uint256(50_000));
        op.preVerificationGas = 50_000;
        op.gasFees = bytes32(uint256(1 gwei) << 128 | uint256(1 gwei));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, entryPoint.getUserOpHash(op));
        op.signature = abi.encodePacked(r, s, v);
    }
}
