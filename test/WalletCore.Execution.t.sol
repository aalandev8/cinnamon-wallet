// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WalletCore} from "../src/WalletCore.sol";
import {MockValidator} from "./mocks/MockValidator.sol";
import {
    CallType,
    ERC7579Utils,
    ExecType,
    Mode,
    ModePayload,
    ModeSelector
} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {Execution} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

contract Target {
    uint256 public value;

    function setValue(uint256 newValue) external payable {
        value = newValue;
    }

    function fail() external pure {
        revert("Target: failed");
    }
}

contract WalletCoreExecutionTest is Test {
    WalletCore wallet;
    Target target;
    address entryPoint;

    function setUp() public {
        entryPoint = makeAddr("entryPoint");
        WalletCore implementation = new WalletCore(entryPoint);
        wallet = WalletCore(payable(Clones.clone(address(implementation))));
        wallet.initialize(address(new MockValidator()), "");
        vm.deal(address(wallet), 10 ether);
        target = new Target();
    }

    function test_execute_single_callsTargetWithValue() public {
        vm.prank(entryPoint);
        wallet.execute(_mode(ERC7579Utils.CALLTYPE_SINGLE, ERC7579Utils.EXECTYPE_DEFAULT), _single(1 ether, 42));

        assertEq(target.value(), 42);
        assertEq(address(target).balance, 1 ether);
    }

    function test_execute_batch_callsEveryTarget() public {
        Target other = new Target();
        Execution[] memory batch = new Execution[](2);
        batch[0] = Execution(address(target), 0, abi.encodeCall(Target.setValue, (1)));
        batch[1] = Execution(address(other), 2 ether, abi.encodeCall(Target.setValue, (2)));

        vm.prank(entryPoint);
        wallet.execute(_mode(ERC7579Utils.CALLTYPE_BATCH, ERC7579Utils.EXECTYPE_DEFAULT), abi.encode(batch));

        assertEq(target.value(), 1);
        assertEq(other.value(), 2);
        assertEq(address(other).balance, 2 ether);
    }

    function test_execute_isCallableBySelf() public {
        vm.prank(address(wallet));
        wallet.execute(_mode(ERC7579Utils.CALLTYPE_SINGLE, ERC7579Utils.EXECTYPE_DEFAULT), _single(0, 7));

        assertEq(target.value(), 7);
    }

    function test_execute_revertsForOtherCallers(address caller) public {
        vm.assume(caller != entryPoint && caller != address(wallet));
        bytes32 mode = _mode(ERC7579Utils.CALLTYPE_SINGLE, ERC7579Utils.EXECTYPE_DEFAULT);
        bytes memory executionCalldata = _single(0, 1);

        vm.prank(caller);
        vm.expectRevert(WalletCore.NotEntryPointOrSelf.selector);
        wallet.execute(mode, executionCalldata);
    }

    function test_execute_bubblesUpTargetRevert() public {
        bytes memory executionCalldata = abi.encodePacked(address(target), uint256(0), abi.encodeCall(Target.fail, ()));
        bytes32 mode = _mode(ERC7579Utils.CALLTYPE_SINGLE, ERC7579Utils.EXECTYPE_DEFAULT);

        vm.prank(entryPoint);
        vm.expectRevert("Target: failed");
        wallet.execute(mode, executionCalldata);
    }

    function test_execute_revertsForUnsupportedModes() public {
        bytes32[3] memory modes = [
            _mode(ERC7579Utils.CALLTYPE_DELEGATECALL, ERC7579Utils.EXECTYPE_DEFAULT),
            _mode(ERC7579Utils.CALLTYPE_SINGLE, ERC7579Utils.EXECTYPE_TRY),
            _mode(ERC7579Utils.CALLTYPE_BATCH, ERC7579Utils.EXECTYPE_TRY)
        ];
        bytes memory executionCalldata = _single(0, 1);

        for (uint256 i; i < modes.length; ++i) {
            vm.prank(entryPoint);
            vm.expectRevert(abi.encodeWithSelector(WalletCore.UnsupportedExecutionMode.selector, modes[i]));
            wallet.execute(modes[i], executionCalldata);
        }
    }

    function test_supportsExecutionMode_matchesExecute() public view {
        assertTrue(wallet.supportsExecutionMode(_mode(ERC7579Utils.CALLTYPE_SINGLE, ERC7579Utils.EXECTYPE_DEFAULT)));
        assertTrue(wallet.supportsExecutionMode(_mode(ERC7579Utils.CALLTYPE_BATCH, ERC7579Utils.EXECTYPE_DEFAULT)));
        assertFalse(
            wallet.supportsExecutionMode(_mode(ERC7579Utils.CALLTYPE_DELEGATECALL, ERC7579Utils.EXECTYPE_DEFAULT))
        );
        assertFalse(wallet.supportsExecutionMode(_mode(ERC7579Utils.CALLTYPE_SINGLE, ERC7579Utils.EXECTYPE_TRY)));
    }

    function _single(uint256 value, uint256 newValue) private view returns (bytes memory) {
        return abi.encodePacked(address(target), value, abi.encodeCall(Target.setValue, (newValue)));
    }

    function _mode(CallType callType, ExecType execType) private pure returns (bytes32) {
        return Mode.unwrap(ERC7579Utils.encodeMode(callType, execType, ModeSelector.wrap(0), ModePayload.wrap(0)));
    }
}
