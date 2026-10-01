// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WalletCore} from "../src/WalletCore.sol";
import {WalletFactory} from "../src/WalletFactory.sol";
import {Module} from "../src/types/Module.sol";
import {MockModule} from "./mocks/MockModule.sol";
import {MockValidator} from "./mocks/MockValidator.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {MODULE_TYPE_HOOK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Test} from "forge-std/Test.sol";

contract WalletFactoryTest is Test {
    EntryPoint entryPoint;
    WalletFactory factory;
    MockValidator rootValidator;
    address senderCreator;
    Module[] noModules;

    function setUp() public {
        entryPoint = new EntryPoint();
        factory = new WalletFactory(address(entryPoint));
        rootValidator = new MockValidator();
        senderCreator = address(entryPoint.senderCreator());
    }

    function test_constructor_deploysImplementationBoundToEntryPoint() public view {
        assertEq(WalletCore(payable(factory.implementation())).entryPoint(), address(entryPoint));
        assertEq(factory.senderCreator(), senderCreator);
    }

    function test_createAccount_deploysAtPredictedAddress() public {
        address predicted = factory.getAddress(address(rootValidator), "owner", noModules, bytes32(0));

        vm.prank(senderCreator);
        address account = factory.createAccount(address(rootValidator), "owner", noModules, bytes32(0));

        assertEq(account, predicted);
        assertGt(account.code.length, 0);
        assertEq(WalletCore(payable(account)).rootValidator(), address(rootValidator));
        assertEq(rootValidator.installData(account), "owner");
    }

    function test_createAccount_installsExtraModules() public {
        MockModule hook = new MockModule(MODULE_TYPE_HOOK);
        Module[] memory extra = new Module[](1);
        extra[0] = Module(MODULE_TYPE_HOOK, address(hook), "limit");

        vm.prank(senderCreator);
        address account = factory.createAccount(address(rootValidator), "", extra, bytes32(0));

        assertTrue(WalletCore(payable(account)).isModuleInstalled(MODULE_TYPE_HOOK, address(hook), ""));
        assertEq(hook.installData(account), "limit");
    }

    function test_createAccount_isIdempotent() public {
        vm.startPrank(senderCreator);
        address first = factory.createAccount(address(rootValidator), "owner", noModules, bytes32(0));
        address second = factory.createAccount(address(rootValidator), "owner", noModules, bytes32(0));

        assertEq(first, second);
    }

    function test_createAccount_revertsForOtherCallers(address caller) public {
        vm.assume(caller != senderCreator);

        vm.prank(caller);
        vm.expectRevert(WalletFactory.NotSenderCreator.selector);
        factory.createAccount(address(rootValidator), "", noModules, bytes32(0));
    }

    function test_getAddress_dependsOnEveryInput() public {
        Module[] memory extra = new Module[](1);
        extra[0] = Module(MODULE_TYPE_HOOK, address(new MockModule(MODULE_TYPE_HOOK)), "");
        address base = factory.getAddress(address(rootValidator), "owner", noModules, bytes32(0));

        assertNotEq(base, factory.getAddress(address(new MockValidator()), "owner", noModules, bytes32(0)));
        assertNotEq(base, factory.getAddress(address(rootValidator), "other", noModules, bytes32(0)));
        assertNotEq(base, factory.getAddress(address(rootValidator), "owner", extra, bytes32(0)));
        assertNotEq(base, factory.getAddress(address(rootValidator), "owner", noModules, bytes32(uint256(1))));
    }

    function test_implementation_cannotBeInitialized() public {
        WalletCore implementation = WalletCore(payable(factory.implementation()));

        vm.expectRevert();
        implementation.initialize(address(rootValidator), "", noModules);
    }
}
