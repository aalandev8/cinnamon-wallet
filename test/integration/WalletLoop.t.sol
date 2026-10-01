// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WalletCore} from "../../src/WalletCore.sol";
import {ECDSAValidator} from "../../src/modules/ECDSAValidator.sol";
import {Module} from "../../src/types/Module.sol";
import {MockHook} from "../mocks/MockHook.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {
    CallType,
    ERC7579Utils,
    Mode,
    ModePayload,
    ModeSelector
} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {Execution, MODULE_TYPE_HOOK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test, Vm} from "forge-std/Test.sol";

contract WalletLoopTest is Test {
    EntryPoint entryPoint;
    WalletCore wallet;
    uint256 ownerKey;
    address payable beneficiary;
    address recipient;

    function setUp() public {
        entryPoint = new EntryPoint();
        ECDSAValidator validator = new ECDSAValidator();
        address owner;
        (owner, ownerKey) = makeAddrAndKey("owner");
        WalletCore implementation = new WalletCore(address(entryPoint));
        wallet = WalletCore(payable(Clones.clone(address(implementation))));
        wallet.initialize(address(validator), abi.encode(owner), new Module[](0));
        vm.deal(address(wallet), 10 ether);
        beneficiary = payable(makeAddr("beneficiary"));
        recipient = makeAddr("recipient");
    }

    function test_ownerSignedUserOp_transfersEth() public {
        _submit(_signed(_executeSingle(recipient, 1 ether, ""), ownerKey));

        assertEq(recipient.balance, 1 ether);
        assertEq(entryPoint.getNonce(address(wallet), 0), 1);
    }

    function test_ownerSignedUserOp_executesBatch() public {
        address other = makeAddr("other");
        Execution[] memory batch = new Execution[](2);
        batch[0] = Execution(recipient, 1 ether, "");
        batch[1] = Execution(other, 2 ether, "");
        bytes memory callData =
            abi.encodeCall(WalletCore.execute, (_mode(ERC7579Utils.CALLTYPE_BATCH), abi.encode(batch)));

        _submit(_signed(callData, ownerKey));

        assertEq(recipient.balance, 1 ether);
        assertEq(other.balance, 2 ether);
    }

    function test_ownerSignedUserOp_installsHookThroughSelfCall() public {
        MockHook hook = new MockHook();
        bytes memory install = abi.encodeCall(WalletCore.installModule, (MODULE_TYPE_HOOK, address(hook), ""));

        _submit(_signed(_executeSingle(address(wallet), 0, install), ownerKey));
        _submit(_signed(_executeSingle(recipient, 1 ether, ""), ownerKey));

        assertTrue(wallet.isModuleInstalled(MODULE_TYPE_HOOK, address(hook), ""));
        assertEq(hook.preCheckCount(), 1);
        assertEq(hook.lastMsgSender(), address(entryPoint));
        assertEq(recipient.balance, 1 ether);
    }

    function test_failingExecution_isReportedButConsumesNonce() public {
        MockHook hook = new MockHook();
        hook.setRejections(true, false);
        bytes memory install = abi.encodeCall(WalletCore.installModule, (MODULE_TYPE_HOOK, address(hook), ""));
        _submit(_signed(_executeSingle(address(wallet), 0, install), ownerKey));

        vm.recordLogs();
        _submit(_signed(_executeSingle(recipient, 1 ether, ""), ownerKey));

        assertFalse(_userOpSucceeded());
        assertEq(recipient.balance, 0);
        assertEq(entryPoint.getNonce(address(wallet), 0), 2);
    }

    function test_userOpSignedByOtherKey_isRejected() public {
        (, uint256 attackerKey) = makeAddrAndKey("attacker");
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _signed(_executeSingle(recipient, 1 ether, ""), attackerKey);

        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(ops, beneficiary);
    }

    function _submit(PackedUserOperation memory op) private {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, beneficiary);
    }

    function _signed(bytes memory callData, uint256 key) private view returns (PackedUserOperation memory op) {
        op.sender = address(wallet);
        op.nonce = entryPoint.getNonce(address(wallet), 0);
        op.callData = callData;
        op.accountGasLimits = bytes32(uint256(200_000) << 128 | uint256(300_000));
        op.preVerificationGas = 50_000;
        op.gasFees = bytes32(uint256(1 gwei) << 128 | uint256(1 gwei));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, entryPoint.getUserOpHash(op));
        op.signature = abi.encodePacked(r, s, v);
    }

    function _executeSingle(address target, uint256 value, bytes memory data) private pure returns (bytes memory) {
        return abi.encodeCall(
            WalletCore.execute, (_mode(ERC7579Utils.CALLTYPE_SINGLE), abi.encodePacked(target, value, data))
        );
    }

    function _mode(CallType callType) private pure returns (bytes32) {
        return Mode.unwrap(
            ERC7579Utils.encodeMode(callType, ERC7579Utils.EXECTYPE_DEFAULT, ModeSelector.wrap(0), ModePayload.wrap(0))
        );
    }

    function _userOpSucceeded() private returns (bool success) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == IEntryPoint.UserOperationEvent.selector) {
                (, success,,) = abi.decode(logs[i].data, (uint256, bool, uint256, uint256));
                return success;
            }
        }
        revert("UserOperationEvent not found");
    }
}
