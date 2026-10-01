// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SpendingLimitHook} from "../../src/modules/SpendingLimitHook.sol";
import {
    CallType,
    ERC7579Utils,
    Mode,
    ModePayload,
    ModeSelector
} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {
    Execution,
    IERC7579Execution,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK,
    MODULE_TYPE_HOOK,
    MODULE_TYPE_VALIDATOR
} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Test} from "forge-std/Test.sol";

contract SpendingLimitHookTest is Test {
    uint256 constant LIMIT = 1 ether;

    SpendingLimitHook hook;
    address account;
    address target;

    function setUp() public {
        vm.warp(30 days);
        hook = new SpendingLimitHook();
        account = makeAddr("account");
        target = makeAddr("target");
        vm.prank(account);
        hook.onInstall(abi.encode(LIMIT));
    }

    function test_isModuleType_onlyHook() public view {
        assertTrue(hook.isModuleType(MODULE_TYPE_HOOK));
        assertFalse(hook.isModuleType(MODULE_TYPE_VALIDATOR));
        assertFalse(hook.isModuleType(MODULE_TYPE_EXECUTOR));
        assertFalse(hook.isModuleType(MODULE_TYPE_FALLBACK));
    }

    function test_onInstall_setsLimitForCallingAccount() public view {
        assertEq(hook.limit(account), LIMIT);
        assertTrue(hook.isInitialized(account));
        assertFalse(hook.isInitialized(address(this)));
    }

    function test_onInstall_revertsWhenAlreadyInstalled() public {
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(SpendingLimitHook.AlreadyInstalled.selector, account));
        hook.onInstall(abi.encode(LIMIT));
    }

    function test_onUninstall_clearsState() public {
        _preCheck(account, _single(0.4 ether));
        vm.prank(account);
        hook.onUninstall("");

        assertFalse(hook.isInitialized(account));
        assertEq(hook.limit(account), 0);
        assertEq(hook.spent(account), 0);
        assertEq(hook.epoch(account), 0);
    }

    function test_preCheck_accruesSpendUnderLimit() public {
        _preCheck(account, _single(0.4 ether));
        _preCheck(account, _single(0.3 ether));
        assertEq(hook.spent(account), 0.7 ether);
    }

    function test_preCheck_allowsSpendExactlyAtLimit() public {
        _preCheck(account, _single(LIMIT));
        assertEq(hook.spent(account), LIMIT);
    }

    function test_preCheck_revertsOverLimit() public {
        _preCheck(account, _single(0.6 ether));
        bytes memory msgData = _single(0.5 ether);
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(SpendingLimitHook.DailyLimitExceeded.selector, 1.1 ether, LIMIT));
        hook.preCheck(address(0), 0, msgData);
    }

    function test_preCheck_resetsOnNewEpoch() public {
        _preCheck(account, _single(LIMIT));
        vm.warp(block.timestamp + 1 days);
        _preCheck(account, _single(0.2 ether));
        assertEq(hook.spent(account), 0.2 ether);
        assertEq(hook.epoch(account), block.timestamp / 1 days);
    }

    function test_preCheck_sumsBatchValues() public {
        Execution[] memory batch = new Execution[](3);
        batch[0] = Execution(target, 0.1 ether, "");
        batch[1] = Execution(target, 0.2 ether, hex"1234");
        batch[2] = Execution(target, 0.3 ether, "");
        _preCheck(account, _batch(batch));
        assertEq(hook.spent(account), 0.6 ether);
    }

    function test_preCheck_revertsWhenBatchSumExceedsLimit() public {
        Execution[] memory batch = new Execution[](2);
        batch[0] = Execution(target, 0.6 ether, "");
        batch[1] = Execution(target, 0.6 ether, "");
        bytes memory msgData = _batch(batch);
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(SpendingLimitHook.DailyLimitExceeded.selector, 1.2 ether, LIMIT));
        hook.preCheck(address(0), 0, msgData);
    }

    function test_preCheck_executeFromExecutorCountsValue() public {
        bytes memory executionCalldata = abi.encodePacked(target, uint256(0.5 ether), bytes(""));
        _preCheck(
            account,
            abi.encodeCall(
                IERC7579Execution.executeFromExecutor, (_mode(ERC7579Utils.CALLTYPE_SINGLE), executionCalldata)
            )
        );
        assertEq(hook.spent(account), 0.5 ether);
    }

    function test_preCheck_delegatecallCountsZero() public {
        bytes memory executionCalldata = abi.encodePacked(target, bytes(""));
        _preCheck(
            account,
            abi.encodeCall(IERC7579Execution.execute, (_mode(ERC7579Utils.CALLTYPE_DELEGATECALL), executionCalldata))
        );
        assertEq(hook.spent(account), 0);
    }

    function test_preCheck_nonExecuteSelectorCountsZero() public {
        _preCheck(account, abi.encodeWithSignature("installModule(uint256,address,bytes)", 1, target, ""));
        assertEq(hook.spent(account), 0);
    }

    function test_setLimit_updatesCallingAccountLimit() public {
        vm.prank(account);
        hook.setLimit(2 ether);
        assertEq(hook.limit(account), 2 ether);
        _preCheck(account, _single(1.5 ether));
    }

    function test_setLimit_revertsWhenNotInstalled() public {
        vm.expectRevert(abi.encodeWithSelector(SpendingLimitHook.NotInitialized.selector, address(this)));
        hook.setLimit(1 ether);
    }

    function test_preCheck_isolatesAccounts() public {
        address other = makeAddr("other");
        vm.prank(other);
        hook.onInstall(abi.encode(LIMIT));

        _preCheck(account, _single(LIMIT));
        _preCheck(other, _single(0.1 ether));

        assertEq(hook.spent(account), LIMIT);
        assertEq(hook.spent(other), 0.1 ether);
    }

    function testFuzz_preCheck_accruesWithinEpoch(uint64 a, uint64 b) public {
        uint256 limit = uint256(a) + uint256(b);
        vm.prank(account);
        hook.setLimit(limit);

        _preCheck(account, _single(a));
        _preCheck(account, _single(b));
        assertEq(hook.spent(account), limit);
    }

    function test_postCheck_isNoop() public {
        vm.prank(account);
        hook.postCheck("");
    }

    function _preCheck(address caller, bytes memory msgData) private {
        vm.prank(caller);
        hook.preCheck(address(0), 0, msgData);
    }

    function _single(uint256 value) private view returns (bytes memory) {
        bytes memory executionCalldata = abi.encodePacked(target, value, bytes(""));
        return abi.encodeCall(IERC7579Execution.execute, (_mode(ERC7579Utils.CALLTYPE_SINGLE), executionCalldata));
    }

    function _batch(Execution[] memory batch) private pure returns (bytes memory) {
        return abi.encodeCall(IERC7579Execution.execute, (_mode(ERC7579Utils.CALLTYPE_BATCH), abi.encode(batch)));
    }

    function _mode(CallType callType) private pure returns (bytes32) {
        return Mode.unwrap(
            ERC7579Utils.encodeMode(
                callType, ERC7579Utils.EXECTYPE_DEFAULT, ModeSelector.wrap(0x00000000), ModePayload.wrap(bytes22(0))
            )
        );
    }
}
