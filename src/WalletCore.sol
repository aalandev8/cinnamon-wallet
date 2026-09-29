// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IAccount, PackedUserOperation} from "@openzeppelin/contracts/interfaces/IERC4337.sol";
import {
    IERC7579Module,
    IERC7579Validator,
    MODULE_TYPE_VALIDATOR,
    VALIDATION_FAILED
} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract WalletCore is IAccount, Initializable {
    /// @custom:storage-location erc7201:cinnamon.storage.WalletCore
    struct WalletStorage {
        address rootValidator;
    }

    // keccak256(abi.encode(uint256(keccak256("cinnamon.storage.WalletCore")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WALLET_STORAGE_SLOT = 0x4eaff713f2ad61ccde02fee3c210dd7b11a4515aa13bdc8426af038fd8095b00;

    address public immutable entryPoint;

    error NotEntryPoint();
    error InvalidRootValidator(address validator);

    constructor(address _entryPoint) {
        entryPoint = _entryPoint;
        _disableInitializers();
    }

    /// @notice Sets the root validator and installs it with `rootInitData`.
    function initialize(address rootValidator_, bytes calldata rootInitData) external initializer {
        if (rootValidator_.code.length == 0 || !IERC7579Module(rootValidator_).isModuleType(MODULE_TYPE_VALIDATOR)) {
            revert InvalidRootValidator(rootValidator_);
        }
        _getWalletStorage().rootValidator = rootValidator_;
        IERC7579Module(rootValidator_).onInstall(rootInitData);
    }

    receive() external payable {}

    /// @notice Routes validation by nonce key: key 0 selects the root validator.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData)
    {
        if (msg.sender != entryPoint) revert NotEntryPoint();

        uint192 nonceKey = uint192(userOp.nonce >> 64);
        if (nonceKey == 0) {
            validationData = IERC7579Validator(_getWalletStorage().rootValidator).validateUserOp(userOp, userOpHash);
        } else {
            validationData = VALIDATION_FAILED;
        }

        _payPrefund(missingAccountFunds);
    }

    function rootValidator() external view returns (address) {
        return _getWalletStorage().rootValidator;
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
