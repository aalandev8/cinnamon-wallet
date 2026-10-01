// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WalletCore} from "../../src/WalletCore.sol";
import {WalletFactory} from "../../src/WalletFactory.sol";
import {ECDSAValidator} from "../../src/modules/ECDSAValidator.sol";
import {SpendingLimitHook} from "../../src/modules/SpendingLimitHook.sol";
import {Module} from "../../src/types/Module.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {
    ERC7579Utils,
    Mode,
    ModePayload,
    ModeSelector
} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {MODULE_TYPE_HOOK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Test, Vm} from "forge-std/Test.sol";

contract CounterfactualWalletTest is Test {
    uint256 constant DAILY_LIMIT = 1 ether;

    EntryPoint entryPoint;
    WalletFactory factory;
    ECDSAValidator validator;
    SpendingLimitHook hook;
    address owner;
    uint256 ownerKey;
    address payable beneficiary;
    address recipient;
    Module[] extraModules;
    address account;

    function setUp() public {
        entryPoint = new EntryPoint();
        factory = new WalletFactory(address(entryPoint));
        validator = new ECDSAValidator();
        hook = new SpendingLimitHook();
        (owner, ownerKey) = makeAddrAndKey("owner");
        beneficiary = payable(makeAddr("beneficiary"));
        recipient = makeAddr("recipient");
        extraModules.push(Module(MODULE_TYPE_HOOK, address(hook), abi.encode(DAILY_LIMIT)));
        account = factory.getAddress(address(validator), abi.encode(owner), extraModules, bytes32(0));
        vm.deal(account, 5 ether);
    }

    function test_firstUserOp_deploysAccountAndTransfers() public {
        assertEq(account.code.length, 0);

        _submit(_signed(_initCode(), _transfer(0.4 ether)));

        assertGt(account.code.length, 0);
        assertEq(WalletCore(payable(account)).rootValidator(), address(validator));
        assertTrue(WalletCore(payable(account)).isModuleInstalled(MODULE_TYPE_HOOK, address(hook), ""));
        assertEq(recipient.balance, 0.4 ether);
        assertEq(hook.spent(account), 0.4 ether);
    }

    function test_spendingLimit_blocksExecutionOverDailyLimit() public {
        _submit(_signed(_initCode(), _transfer(0.6 ether)));

        vm.recordLogs();
        _submit(_signed("", _transfer(0.6 ether)));

        assertFalse(_userOpSucceeded());
        assertEq(recipient.balance, 0.6 ether);
    }

    function test_spendingLimit_resetsOnNextDay() public {
        _submit(_signed(_initCode(), _transfer(1 ether)));
        vm.warp(block.timestamp + 1 days);

        _submit(_signed("", _transfer(1 ether)));

        assertEq(recipient.balance, 2 ether);
    }

    function test_firstUserOp_withForeignSignature_doesNotDeploy() public {
        (, uint256 attackerKey) = makeAddrAndKey("attacker");
        PackedUserOperation memory op = _userOp(_initCode(), _transfer(1 ether));
        op.signature = _sign(attackerKey, op);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(ops, beneficiary);
        assertEq(account.code.length, 0);
    }

    function _initCode() private view returns (bytes memory) {
        return abi.encodePacked(
            address(factory),
            abi.encodeCall(
                WalletFactory.createAccount, (address(validator), abi.encode(owner), extraModules, bytes32(0))
            )
        );
    }

    function _transfer(uint256 value) private view returns (bytes memory) {
        bytes32 mode = Mode.unwrap(
            ERC7579Utils.encodeMode(
                ERC7579Utils.CALLTYPE_SINGLE, ERC7579Utils.EXECTYPE_DEFAULT, ModeSelector.wrap(0), ModePayload.wrap(0)
            )
        );
        return abi.encodeCall(WalletCore.execute, (mode, abi.encodePacked(recipient, value)));
    }

    function _userOp(bytes memory initCode, bytes memory callData)
        private
        view
        returns (PackedUserOperation memory op)
    {
        op.sender = account;
        op.nonce = entryPoint.getNonce(account, 0);
        op.initCode = initCode;
        op.callData = callData;
        op.accountGasLimits = bytes32(uint256(1_000_000) << 128 | uint256(300_000));
        op.preVerificationGas = 50_000;
        op.gasFees = bytes32(uint256(1 gwei) << 128 | uint256(1 gwei));
    }

    function _signed(bytes memory initCode, bytes memory callData)
        private
        view
        returns (PackedUserOperation memory op)
    {
        op = _userOp(initCode, callData);
        op.signature = _sign(ownerKey, op);
    }

    function _sign(uint256 key, PackedUserOperation memory op) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, entryPoint.getUserOpHash(op));
        return abi.encodePacked(r, s, v);
    }

    function _submit(PackedUserOperation memory op) private {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, beneficiary);
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
