// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WalletCore} from "../src/WalletCore.sol";
import {Module} from "../src/types/Module.sol";
import {MockHook} from "./mocks/MockHook.sol";
import {MockModule} from "./mocks/MockModule.sol";
import {MockValidator} from "./mocks/MockValidator.sol";
import {
    ERC7579Utils,
    Mode,
    ModePayload,
    ModeSelector
} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {MODULE_TYPE_EXECUTOR, MODULE_TYPE_HOOK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

contract WalletCoreHookTest is Test {
    WalletCore wallet;
    MockHook hook;
    address entryPoint;
    address recipient;
    bytes32 singleMode;

    function setUp() public {
        entryPoint = makeAddr("entryPoint");
        recipient = makeAddr("recipient");
        WalletCore implementation = new WalletCore(entryPoint);
        wallet = WalletCore(payable(Clones.clone(address(implementation))));
        wallet.initialize(address(new MockValidator()), "", new Module[](0));
        vm.deal(address(wallet), 10 ether);
        singleMode = Mode.unwrap(
            ERC7579Utils.encodeMode(
                ERC7579Utils.CALLTYPE_SINGLE, ERC7579Utils.EXECTYPE_DEFAULT, ModeSelector.wrap(0), ModePayload.wrap(0)
            )
        );
        hook = new MockHook();
        vm.prank(entryPoint);
        wallet.installModule(MODULE_TYPE_HOOK, address(hook), "");
    }

    function test_execute_wrapsCallWithPreAndPostCheck() public {
        bytes memory executionCalldata = abi.encodePacked(recipient, uint256(1 ether));

        vm.prank(entryPoint);
        wallet.execute(singleMode, executionCalldata);

        assertEq(hook.preCheckCount(), 1);
        assertEq(hook.lastMsgSender(), entryPoint);
        assertEq(hook.lastMsgData(), abi.encodeCall(WalletCore.execute, (singleMode, executionCalldata)));
        assertEq(hook.lastHookData(), abi.encode(uint256(1)));
        assertEq(recipient.balance, 1 ether);
    }

    function test_execute_revertsWhenPreCheckRejects() public {
        hook.setRejections(true, false);
        bytes memory executionCalldata = abi.encodePacked(recipient, uint256(1 ether));

        vm.prank(entryPoint);
        vm.expectRevert(MockHook.PreCheckRejected.selector);
        wallet.execute(singleMode, executionCalldata);
    }

    function test_execute_revertsWhenPostCheckRejects() public {
        hook.setRejections(false, true);
        bytes memory executionCalldata = abi.encodePacked(recipient, uint256(1 ether));

        vm.prank(entryPoint);
        vm.expectRevert(MockHook.PostCheckRejected.selector);
        wallet.execute(singleMode, executionCalldata);
    }

    function test_execute_skipsHookAfterUninstall() public {
        vm.startPrank(entryPoint);
        wallet.uninstallModule(MODULE_TYPE_HOOK, address(hook), "");
        wallet.execute(singleMode, abi.encodePacked(recipient, uint256(1 ether)));

        assertEq(hook.preCheckCount(), 0);
        assertEq(recipient.balance, 1 ether);
    }

    function test_executeFromExecutor_runsThroughHookAndReturnsResults() public {
        address executor = address(new MockModule(MODULE_TYPE_EXECUTOR));
        vm.prank(entryPoint);
        wallet.installModule(MODULE_TYPE_EXECUTOR, executor, "");

        vm.prank(executor);
        bytes[] memory results = wallet.executeFromExecutor(singleMode, abi.encodePacked(recipient, uint256(1 ether)));

        assertEq(results.length, 1);
        assertEq(hook.preCheckCount(), 1);
        assertEq(hook.lastMsgSender(), executor);
        assertEq(recipient.balance, 1 ether);
    }

    function test_executeFromExecutor_revertsForUninstalledExecutor(address caller) public {
        bytes memory executionCalldata = abi.encodePacked(recipient, uint256(1 ether));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(WalletCore.ModuleNotInstalled.selector, MODULE_TYPE_EXECUTOR, caller));
        wallet.executeFromExecutor(singleMode, executionCalldata);
    }
}
