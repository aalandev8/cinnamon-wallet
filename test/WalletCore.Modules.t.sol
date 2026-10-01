// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WalletCore} from "../src/WalletCore.sol";
import {Module} from "../src/types/Module.sol";
import {MockModule} from "./mocks/MockModule.sol";
import {MockValidator} from "./mocks/MockValidator.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/IERC4337.sol";
import {
    IERC7579ModuleConfig,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK,
    MODULE_TYPE_HOOK,
    MODULE_TYPE_VALIDATOR,
    VALIDATION_FAILED
} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Test} from "forge-std/Test.sol";

contract WalletCoreModulesTest is Test {
    WalletCore wallet;
    MockValidator rootValidator;
    address entryPoint;

    function setUp() public {
        entryPoint = makeAddr("entryPoint");
        WalletCore implementation = new WalletCore(entryPoint);
        wallet = WalletCore(payable(Clones.clone(address(implementation))));
        rootValidator = new MockValidator();
        wallet.initialize(address(rootValidator), "", new Module[](0));
    }

    function test_installModule_installsEachSupportedType() public {
        uint256[3] memory types = [MODULE_TYPE_VALIDATOR, MODULE_TYPE_EXECUTOR, MODULE_TYPE_HOOK];
        for (uint256 i; i < types.length; ++i) {
            MockModule module = new MockModule(types[i]);

            vm.expectEmit(address(wallet));
            emit IERC7579ModuleConfig.ModuleInstalled(types[i], address(module));
            vm.prank(entryPoint);
            wallet.installModule(types[i], address(module), "init");

            assertTrue(wallet.isModuleInstalled(types[i], address(module), ""));
            assertEq(module.installData(address(wallet)), "init");
        }
    }

    function test_installModule_isCallableBySelf() public {
        MockModule module = new MockModule(MODULE_TYPE_EXECUTOR);

        vm.prank(address(wallet));
        wallet.installModule(MODULE_TYPE_EXECUTOR, address(module), "");

        assertTrue(wallet.isModuleInstalled(MODULE_TYPE_EXECUTOR, address(module), ""));
    }

    function test_installModule_revertsForOtherCallers(address caller) public {
        vm.assume(caller != entryPoint && caller != address(wallet));
        MockModule module = new MockModule(MODULE_TYPE_EXECUTOR);

        vm.prank(caller);
        vm.expectRevert(WalletCore.NotEntryPointOrSelf.selector);
        wallet.installModule(MODULE_TYPE_EXECUTOR, address(module), "");
    }

    function test_installModule_revertsOnTypeMismatch() public {
        MockModule module = new MockModule(MODULE_TYPE_EXECUTOR);

        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(WalletCore.ModuleTypeMismatch.selector, MODULE_TYPE_VALIDATOR, address(module))
        );
        wallet.installModule(MODULE_TYPE_VALIDATOR, address(module), "");
    }

    function test_installModule_revertsForUnsupportedType() public {
        MockModule module = new MockModule(MODULE_TYPE_FALLBACK);

        vm.prank(entryPoint);
        vm.expectRevert(abi.encodeWithSelector(WalletCore.UnsupportedModuleType.selector, MODULE_TYPE_FALLBACK));
        wallet.installModule(MODULE_TYPE_FALLBACK, address(module), "");
    }

    function test_installModule_revertsWhenAlreadyInstalled() public {
        MockModule module = new MockModule(MODULE_TYPE_EXECUTOR);
        vm.startPrank(entryPoint);
        wallet.installModule(MODULE_TYPE_EXECUTOR, address(module), "");

        vm.expectRevert(
            abi.encodeWithSelector(WalletCore.ModuleAlreadyInstalled.selector, MODULE_TYPE_EXECUTOR, address(module))
        );
        wallet.installModule(MODULE_TYPE_EXECUTOR, address(module), "");
    }

    function test_installModule_revertsOnSecondHook() public {
        vm.startPrank(entryPoint);
        wallet.installModule(MODULE_TYPE_HOOK, address(new MockModule(MODULE_TYPE_HOOK)), "");

        address second = address(new MockModule(MODULE_TYPE_HOOK));
        vm.expectRevert(WalletCore.HookAlreadyInstalled.selector);
        wallet.installModule(MODULE_TYPE_HOOK, second, "");
    }

    function test_uninstallModule_removesModuleAndCallsOnUninstall() public {
        MockModule module = new MockModule(MODULE_TYPE_HOOK);
        vm.startPrank(entryPoint);
        wallet.installModule(MODULE_TYPE_HOOK, address(module), "init");

        vm.expectEmit(address(wallet));
        emit IERC7579ModuleConfig.ModuleUninstalled(MODULE_TYPE_HOOK, address(module));
        wallet.uninstallModule(MODULE_TYPE_HOOK, address(module), "bye");

        assertFalse(wallet.isModuleInstalled(MODULE_TYPE_HOOK, address(module), ""));
        assertEq(module.installData(address(wallet)), "");
        assertEq(module.uninstallData(address(wallet)), "bye");
    }

    function test_uninstallModule_revertsWhenNotInstalled() public {
        MockModule module = new MockModule(MODULE_TYPE_EXECUTOR);

        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(WalletCore.ModuleNotInstalled.selector, MODULE_TYPE_EXECUTOR, address(module))
        );
        wallet.uninstallModule(MODULE_TYPE_EXECUTOR, address(module), "");
    }

    function test_uninstallModule_revertsForRootValidator() public {
        vm.prank(entryPoint);
        vm.expectRevert(WalletCore.CannotUninstallRootValidator.selector);
        wallet.uninstallModule(MODULE_TYPE_VALIDATOR, address(rootValidator), "");
    }

    function test_rootValidator_isReportedAsInstalled() public view {
        assertTrue(wallet.isModuleInstalled(MODULE_TYPE_VALIDATOR, address(rootValidator), ""));
    }

    function test_validateUserOp_routesNonceKeyToInstalledValidator() public {
        MockValidator validator = new MockValidator();
        validator.setValidationResult(7);
        vm.prank(entryPoint);
        wallet.installModule(MODULE_TYPE_VALIDATOR, address(validator), "");

        PackedUserOperation memory op;
        op.nonce = uint256(uint192(uint160(address(validator)))) << 64;
        vm.prank(entryPoint);
        assertEq(wallet.validateUserOp(op, bytes32(0), 0), 7);
    }

    function test_validateUserOp_failsForUninstalledValidatorKey() public {
        MockValidator validator = new MockValidator();
        PackedUserOperation memory op;
        op.nonce = uint256(uint192(uint160(address(validator)))) << 64;

        vm.prank(entryPoint);
        assertEq(wallet.validateUserOp(op, bytes32(0), 0), VALIDATION_FAILED);
    }

    function test_supportsModule() public view {
        assertTrue(wallet.supportsModule(MODULE_TYPE_VALIDATOR));
        assertTrue(wallet.supportsModule(MODULE_TYPE_EXECUTOR));
        assertTrue(wallet.supportsModule(MODULE_TYPE_HOOK));
        assertFalse(wallet.supportsModule(MODULE_TYPE_FALLBACK));
        assertFalse(wallet.supportsModule(5));
    }

    function test_accountId() public view {
        assertEq(wallet.accountId(), "cinnamon.wallet.0.1.0");
    }

    function test_changeRootValidator_swapsRootAtomically() public {
        MockValidator newRoot = new MockValidator();
        rootValidator.onInstall("");

        vm.expectEmit(address(wallet));
        emit WalletCore.RootValidatorChanged(address(rootValidator), address(newRoot));
        vm.prank(entryPoint);
        wallet.changeRootValidator(address(newRoot), "init");

        assertEq(wallet.rootValidator(), address(newRoot));
        assertEq(newRoot.installData(address(wallet)), "init");
        assertTrue(wallet.isModuleInstalled(MODULE_TYPE_VALIDATOR, address(newRoot), ""));
        assertFalse(wallet.isModuleInstalled(MODULE_TYPE_VALIDATOR, address(rootValidator), ""));
    }

    function test_changeRootValidator_routesKeyZeroToNewRoot() public {
        MockValidator newRoot = new MockValidator();
        newRoot.setValidationResult(9);
        vm.prank(entryPoint);
        wallet.changeRootValidator(address(newRoot), "");

        PackedUserOperation memory op;
        vm.prank(entryPoint);
        assertEq(wallet.validateUserOp(op, bytes32(0), 0), 9);
    }

    function test_changeRootValidator_promotesInstalledValidator() public {
        MockValidator validator = new MockValidator();
        vm.startPrank(entryPoint);
        wallet.installModule(MODULE_TYPE_VALIDATOR, address(validator), "");

        wallet.changeRootValidator(address(validator), "");

        assertEq(wallet.rootValidator(), address(validator));
        vm.expectRevert(WalletCore.CannotUninstallRootValidator.selector);
        wallet.uninstallModule(MODULE_TYPE_VALIDATOR, address(validator), "");
    }

    function test_changeRootValidator_revertsForInvalidValidator() public {
        address notValidator = address(new MockModule(MODULE_TYPE_EXECUTOR));

        vm.startPrank(entryPoint);
        vm.expectRevert(abi.encodeWithSelector(WalletCore.InvalidRootValidator.selector, notValidator));
        wallet.changeRootValidator(notValidator, "");

        vm.expectRevert(abi.encodeWithSelector(WalletCore.InvalidRootValidator.selector, address(rootValidator)));
        wallet.changeRootValidator(address(rootValidator), "");
    }

    function test_changeRootValidator_revertsForOtherCallers(address caller) public {
        vm.assume(caller != entryPoint && caller != address(wallet));
        MockValidator newRoot = new MockValidator();

        vm.prank(caller);
        vm.expectRevert(WalletCore.NotEntryPointOrSelf.selector);
        wallet.changeRootValidator(address(newRoot), "");
    }
}
