// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Module} from "./types/Module.sol";
import {CallType, ERC7579Utils, ExecType, Mode} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {IAccount, PackedUserOperation} from "@openzeppelin/contracts/interfaces/IERC4337.sol";
import {
    IERC7579Hook,
    IERC7579Module,
    IERC7579ModuleConfig,
    IERC7579Validator,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_HOOK,
    MODULE_TYPE_VALIDATOR,
    VALIDATION_FAILED
} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract WalletCore is IAccount, IERC7579ModuleConfig, Initializable {
    /// @custom:storage-location erc7201:cinnamon.storage.WalletCore
    struct WalletStorage {
        address rootValidator;
        address hook;
        mapping(address module => bool) validators;
        mapping(address module => bool) executors;
    }

    // keccak256(abi.encode(uint256(keccak256("cinnamon.storage.WalletCore")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WALLET_STORAGE_SLOT = 0x4eaff713f2ad61ccde02fee3c210dd7b11a4515aa13bdc8426af038fd8095b00;

    address public immutable entryPoint;

    event RootValidatorChanged(address indexed previousRoot, address indexed newRoot);

    error NotEntryPoint();
    error InvalidRootValidator(address validator);
    error NotEntryPointOrSelf();
    error UnsupportedExecutionMode(bytes32 mode);
    error UnsupportedModuleType(uint256 moduleTypeId);
    error ModuleTypeMismatch(uint256 moduleTypeId, address module);
    error ModuleAlreadyInstalled(uint256 moduleTypeId, address module);
    error ModuleNotInstalled(uint256 moduleTypeId, address module);
    error HookAlreadyInstalled();
    error CannotUninstallRootValidator();

    modifier onlyEntryPointOrSelf() {
        if (msg.sender != entryPoint && msg.sender != address(this)) revert NotEntryPointOrSelf();
        _;
    }

    modifier onlyExecutor() {
        if (!_getWalletStorage().executors[msg.sender]) revert ModuleNotInstalled(MODULE_TYPE_EXECUTOR, msg.sender);
        _;
    }

    modifier withHook() {
        address hook = _getWalletStorage().hook;
        if (hook == address(0)) {
            _;
        } else {
            bytes memory hookData = IERC7579Hook(hook).preCheck(msg.sender, msg.value, msg.data);
            _;
            IERC7579Hook(hook).postCheck(hookData);
        }
    }

    constructor(address _entryPoint) {
        entryPoint = _entryPoint;
        _disableInitializers();
    }

    /// @notice Sets and installs the root validator, then installs `extraModules` in order.
    function initialize(address rootValidator_, bytes calldata rootInitData, Module[] calldata extraModules)
        external
        initializer
    {
        _requireValidRoot(rootValidator_);
        _getWalletStorage().rootValidator = rootValidator_;
        IERC7579Module(rootValidator_).onInstall(rootInitData);

        for (uint256 i; i < extraModules.length; ++i) {
            _installModule(extraModules[i].moduleType, extraModules[i].moduleAddress, extraModules[i].initData);
        }
    }

    receive() external payable {}

    /// @notice Routes validation by nonce key: key 0 selects the root validator.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData)
    {
        if (msg.sender != entryPoint) revert NotEntryPoint();

        uint192 nonceKey = uint192(userOp.nonce >> 64);
        address validator = nonceKey == 0 ? _getWalletStorage().rootValidator : address(uint160(nonceKey));
        if (nonceKey == 0 || (nonceKey >> 160 == 0 && _getWalletStorage().validators[validator])) {
            validationData = IERC7579Validator(validator).validateUserOp(userOp, userOpHash);
        } else {
            validationData = VALIDATION_FAILED;
        }

        _payPrefund(missingAccountFunds);
    }

    /// @notice Executes a single or batch call with revert-on-failure semantics.
    function execute(bytes32 mode, bytes calldata executionCalldata) external payable onlyEntryPointOrSelf withHook {
        _execute(mode, executionCalldata);
    }

    function executeFromExecutor(bytes32 mode, bytes calldata executionCalldata)
        external
        payable
        onlyExecutor
        withHook
        returns (bytes[] memory returnData)
    {
        returnData = _execute(mode, executionCalldata);
    }

    function supportsExecutionMode(bytes32 mode) public pure returns (bool) {
        (CallType callType, ExecType execType,,) = ERC7579Utils.decodeMode(Mode.wrap(mode));
        return execType == ERC7579Utils.EXECTYPE_DEFAULT
            && (callType == ERC7579Utils.CALLTYPE_SINGLE || callType == ERC7579Utils.CALLTYPE_BATCH);
    }

    /// @notice Atomically replaces the root validator; an already installed validator is promoted as is.
    function changeRootValidator(address newRoot, bytes calldata initData) external onlyEntryPointOrSelf {
        WalletStorage storage $ = _getWalletStorage();
        address previousRoot = $.rootValidator;
        if (newRoot == previousRoot) revert InvalidRootValidator(newRoot);
        _requireValidRoot(newRoot);

        $.rootValidator = newRoot;
        if ($.validators[newRoot]) {
            delete $.validators[newRoot];
        } else {
            IERC7579Module(newRoot).onInstall(initData);
        }
        IERC7579Module(previousRoot).onUninstall("");

        emit RootValidatorChanged(previousRoot, newRoot);
    }

    function installModule(uint256 moduleTypeId, address module, bytes calldata initData)
        external
        onlyEntryPointOrSelf
    {
        _installModule(moduleTypeId, module, initData);
    }

    function uninstallModule(uint256 moduleTypeId, address module, bytes calldata deInitData)
        external
        onlyEntryPointOrSelf
    {
        WalletStorage storage $ = _getWalletStorage();
        if (moduleTypeId == MODULE_TYPE_VALIDATOR && module == $.rootValidator) revert CannotUninstallRootValidator();
        if (!_isModuleInstalled(moduleTypeId, module)) revert ModuleNotInstalled(moduleTypeId, module);

        if (moduleTypeId == MODULE_TYPE_VALIDATOR) {
            delete $.validators[module];
        } else if (moduleTypeId == MODULE_TYPE_EXECUTOR) {
            delete $.executors[module];
        } else {
            delete $.hook;
        }

        IERC7579Module(module).onUninstall(deInitData);
        emit ModuleUninstalled(moduleTypeId, module);
    }

    function isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata) external view returns (bool) {
        return _isModuleInstalled(moduleTypeId, module);
    }

    function supportsModule(uint256 moduleTypeId) public pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR || moduleTypeId == MODULE_TYPE_EXECUTOR
            || moduleTypeId == MODULE_TYPE_HOOK;
    }

    function accountId() external pure returns (string memory) {
        return "cinnamon.wallet.0.1.0";
    }

    function rootValidator() external view returns (address) {
        return _getWalletStorage().rootValidator;
    }

    function _execute(bytes32 mode, bytes calldata executionCalldata) private returns (bytes[] memory) {
        if (!supportsExecutionMode(mode)) revert UnsupportedExecutionMode(mode);
        (CallType callType,,,) = ERC7579Utils.decodeMode(Mode.wrap(mode));
        if (callType == ERC7579Utils.CALLTYPE_SINGLE) {
            return ERC7579Utils.execSingle(executionCalldata, ERC7579Utils.EXECTYPE_DEFAULT);
        }
        return ERC7579Utils.execBatch(executionCalldata, ERC7579Utils.EXECTYPE_DEFAULT);
    }

    function _installModule(uint256 moduleTypeId, address module, bytes calldata initData) private {
        if (!supportsModule(moduleTypeId)) revert UnsupportedModuleType(moduleTypeId);
        if (!IERC7579Module(module).isModuleType(moduleTypeId)) revert ModuleTypeMismatch(moduleTypeId, module);
        if (_isModuleInstalled(moduleTypeId, module)) revert ModuleAlreadyInstalled(moduleTypeId, module);

        WalletStorage storage $ = _getWalletStorage();
        if (moduleTypeId == MODULE_TYPE_VALIDATOR) {
            $.validators[module] = true;
        } else if (moduleTypeId == MODULE_TYPE_EXECUTOR) {
            $.executors[module] = true;
        } else {
            if ($.hook != address(0)) revert HookAlreadyInstalled();
            $.hook = module;
        }

        IERC7579Module(module).onInstall(initData);
        emit ModuleInstalled(moduleTypeId, module);
    }

    function _requireValidRoot(address validator) private view {
        if (validator.code.length == 0 || !IERC7579Module(validator).isModuleType(MODULE_TYPE_VALIDATOR)) {
            revert InvalidRootValidator(validator);
        }
    }

    function _isModuleInstalled(uint256 moduleTypeId, address module) private view returns (bool) {
        WalletStorage storage $ = _getWalletStorage();
        if (moduleTypeId == MODULE_TYPE_VALIDATOR) return module == $.rootValidator || $.validators[module];
        if (moduleTypeId == MODULE_TYPE_EXECUTOR) return $.executors[module];
        if (moduleTypeId == MODULE_TYPE_HOOK) return module != address(0) && module == $.hook;
        return false;
    }

    function _payPrefund(uint256 missingAccountFunds) private {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            (success);
        }
    }

    function _getWalletStorage() private pure returns (WalletStorage storage $) {
        assembly {
            $.slot := WALLET_STORAGE_SLOT
        }
    }
}
