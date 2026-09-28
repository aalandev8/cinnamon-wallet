// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/IERC4337.sol";
import {IERC7579Validator, MODULE_TYPE_VALIDATOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

contract MockValidator is IERC7579Validator {
    mapping(address account => bytes data) public installData;
    uint256 public validationResult;

    function setValidationResult(uint256 result) external {
        validationResult = result;
    }

    function onInstall(bytes calldata data) external {
        installData[msg.sender] = data;
    }

    function onUninstall(bytes calldata) external {
        delete installData[msg.sender];
    }

    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    function validateUserOp(PackedUserOperation calldata, bytes32) external view returns (uint256) {
        return validationResult;
    }

    function isValidSignatureWithSender(address, bytes32, bytes calldata) external pure returns (bytes4) {
        return 0xffffffff;
    }
}
