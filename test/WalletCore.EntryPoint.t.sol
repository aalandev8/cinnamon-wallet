// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WalletCore} from "../src/WalletCore.sol";
import {MockValidator} from "./mocks/MockValidator.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

contract WalletCoreEntryPointTest is Test {
    EntryPoint entryPoint;
    WalletCore wallet;
    MockValidator rootValidator;
    address payable beneficiary;

    function setUp() public {
        entryPoint = new EntryPoint();
        WalletCore implementation = new WalletCore(address(entryPoint));
        wallet = WalletCore(payable(Clones.clone(address(implementation))));
        rootValidator = new MockValidator();
        wallet.initialize(address(rootValidator), "");
        vm.deal(address(wallet), 1 ether);
        beneficiary = payable(makeAddr("beneficiary"));
    }

    function test_handleOps_executesUserOpValidatedByRootValidator() public {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _userOp(entryPoint.getNonce(address(wallet), 0));

        entryPoint.handleOps(ops, beneficiary);

        assertEq(entryPoint.getNonce(address(wallet), 0), 1);
        assertGt(beneficiary.balance, 0);
        assertEq(address(wallet).balance + entryPoint.balanceOf(address(wallet)) + beneficiary.balance, 1 ether);
    }

    function test_handleOps_revertsWhenRootValidatorRejects() public {
        rootValidator.setValidationResult(1);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _userOp(entryPoint.getNonce(address(wallet), 0));

        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(ops, beneficiary);
    }

    function test_handleOps_revertsWhenNonceKeyHasNoValidator() public {
        uint192 key = 1;
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _userOp(entryPoint.getNonce(address(wallet), key));

        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(ops, beneficiary);
    }

    function _userOp(uint256 nonce) private view returns (PackedUserOperation memory op) {
        op.sender = address(wallet);
        op.nonce = nonce;
        op.accountGasLimits = bytes32(uint256(200_000) << 128 | uint256(50_000));
        op.preVerificationGas = 50_000;
        op.gasFees = bytes32(uint256(1 gwei) << 128 | uint256(1 gwei));
    }
}
