// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WalletCore} from "../src/WalletCore.sol";
import {Module} from "../src/types/Module.sol";
import {MockModule} from "./mocks/MockModule.sol";
import {MockValidator} from "./mocks/MockValidator.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/IERC4337.sol";
import {
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_HOOK,
    MODULE_TYPE_VALIDATOR,
    VALIDATION_FAILED
} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

contract WalletCoreTest is Test {
    bytes32 constant WALLET_STORAGE_SLOT =
        keccak256(abi.encode(uint256(keccak256("cinnamon.storage.WalletCore")) - 1)) & ~bytes32(uint256(0xff));

    WalletCore implementation;
    WalletCore wallet;
    MockValidator rootValidator;
    address entryPoint;

    function setUp() public {
        entryPoint = makeAddr("entryPoint");
        implementation = new WalletCore(entryPoint);
        wallet = WalletCore(payable(Clones.clone(address(implementation))));
        rootValidator = new MockValidator();
    }

    function test_storesEntryPoint() public view {
        assertEq(wallet.entryPoint(), entryPoint);
    }

    function test_validateUserOp_revertsWhenCallerIsNotEntryPoint(address caller) public {
        vm.assume(caller != entryPoint);
        PackedUserOperation memory userOp;

        vm.prank(caller);
        vm.expectRevert(WalletCore.NotEntryPoint.selector);
        wallet.validateUserOp(userOp, bytes32(0), 0);
    }

    function test_storageSlot_matchesErc7201Formula() public pure {
        assertEq(WALLET_STORAGE_SLOT, 0x4eaff713f2ad61ccde02fee3c210dd7b11a4515aa13bdc8426af038fd8095b00);
    }

    function test_initialize_setsRootValidatorInNamespacedSlot() public {
        wallet.initialize(address(rootValidator), "", new Module[](0));

        assertEq(wallet.rootValidator(), address(rootValidator));
        assertEq(address(uint160(uint256(vm.load(address(wallet), WALLET_STORAGE_SLOT)))), address(rootValidator));
    }

    function test_initialize_callsOnInstallWithRootInitData() public {
        bytes memory initData = abi.encode(makeAddr("owner"));

        wallet.initialize(address(rootValidator), initData, new Module[](0));

        assertEq(rootValidator.installData(address(wallet)), initData);
    }

    function test_initialize_revertsWhenCalledTwice() public {
        wallet.initialize(address(rootValidator), "", new Module[](0));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        wallet.initialize(address(rootValidator), "", new Module[](0));
    }

    function test_initialize_revertsOnImplementation() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(rootValidator), "", new Module[](0));
    }

    function test_initialize_revertsWhenRootIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(WalletCore.InvalidRootValidator.selector, address(0)));
        wallet.initialize(address(0), "", new Module[](0));
    }

    function test_initialize_revertsWhenRootIsNotAValidator() public {
        address notValidator = address(new NotAValidator());

        vm.expectRevert(abi.encodeWithSelector(WalletCore.InvalidRootValidator.selector, notValidator));
        wallet.initialize(notValidator, "", new Module[](0));
    }

    function test_validateUserOp_routesNonceKeyZeroToRootValidator(uint64 sequence, uint256 result) public {
        wallet.initialize(address(rootValidator), "", new Module[](0));
        rootValidator.setValidationResult(result);
        PackedUserOperation memory userOp;
        userOp.nonce = sequence;

        vm.prank(entryPoint);
        assertEq(wallet.validateUserOp(userOp, keccak256("userOp"), 0), result);
    }

    function test_validateUserOp_failsWhenNonceKeyValidatorIsNotInstalled(uint192 key, uint64 sequence) public {
        vm.assume(key != 0);
        wallet.initialize(address(rootValidator), "", new Module[](0));
        PackedUserOperation memory userOp;
        userOp.nonce = (uint256(key) << 64) | sequence;

        vm.prank(entryPoint);
        assertEq(wallet.validateUserOp(userOp, keccak256("userOp"), 0), VALIDATION_FAILED);
    }

    function test_validateUserOp_paysMissingFundsToEntryPoint(uint96 missingFunds) public {
        wallet.initialize(address(rootValidator), "", new Module[](0));
        vm.deal(address(wallet), missingFunds);
        PackedUserOperation memory userOp;

        vm.prank(entryPoint);
        wallet.validateUserOp(userOp, keccak256("userOp"), missingFunds);

        assertEq(entryPoint.balance, missingFunds);
        assertEq(address(wallet).balance, 0);
    }

    function test_receive_acceptsEther() public {
        vm.deal(address(this), 1 ether);

        (bool success,) = address(wallet).call{value: 1 ether}("");

        assertTrue(success);
        assertEq(address(wallet).balance, 1 ether);
    }

    function test_initialize_installsExtraModules() public {
        MockModule executor = new MockModule(MODULE_TYPE_EXECUTOR);
        MockModule hook = new MockModule(MODULE_TYPE_HOOK);
        Module[] memory extra = new Module[](2);
        extra[0] = Module(MODULE_TYPE_EXECUTOR, address(executor), "exec");
        extra[1] = Module(MODULE_TYPE_HOOK, address(hook), "hook");

        wallet.initialize(address(rootValidator), "", extra);

        assertTrue(wallet.isModuleInstalled(MODULE_TYPE_EXECUTOR, address(executor), ""));
        assertTrue(wallet.isModuleInstalled(MODULE_TYPE_HOOK, address(hook), ""));
        assertEq(executor.installData(address(wallet)), "exec");
        assertEq(hook.installData(address(wallet)), "hook");
    }

    function test_initialize_revertsOnInvalidExtraModule() public {
        MockModule executor = new MockModule(MODULE_TYPE_EXECUTOR);
        Module[] memory extra = new Module[](1);
        extra[0] = Module(MODULE_TYPE_HOOK, address(executor), "");

        vm.expectRevert(
            abi.encodeWithSelector(WalletCore.ModuleTypeMismatch.selector, MODULE_TYPE_HOOK, address(executor))
        );
        wallet.initialize(address(rootValidator), "", extra);
    }

    function test_initialize_revertsWhenRootIsRepeatedAsExtraModule() public {
        Module[] memory extra = new Module[](1);
        extra[0] = Module(MODULE_TYPE_VALIDATOR, address(rootValidator), "");

        vm.expectRevert(
            abi.encodeWithSelector(
                WalletCore.ModuleAlreadyInstalled.selector, MODULE_TYPE_VALIDATOR, address(rootValidator)
            )
        );
        wallet.initialize(address(rootValidator), "", extra);
    }
}

contract NotAValidator {
    function isModuleType(uint256) external pure returns (bool) {
        return false;
    }
}
