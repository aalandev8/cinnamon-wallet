// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/IERC4337.sol";
import {
    IERC7579Validator,
    MODULE_TYPE_VALIDATOR,
    VALIDATION_FAILED,
    VALIDATION_SUCCESS
} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice Single-owner ECDSA validator. Storage is keyed by the calling account.
contract ECDSAValidator is IERC7579Validator {
    mapping(address account => address) public owner;

    error InvalidOwner();
    error AlreadyInstalled(address account);

    function onInstall(bytes calldata data) external {
        if (owner[msg.sender] != address(0)) revert AlreadyInstalled(msg.sender);
        address newOwner = abi.decode(data, (address));
        if (newOwner == address(0)) revert InvalidOwner();
        owner[msg.sender] = newOwner;
    }

    function onUninstall(bytes calldata) external {
        delete owner[msg.sender];
    }

    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    /// @dev `userOpHash` is the EntryPoint v0.8 EIP-712 digest, so it is recovered as-is.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) external view returns (uint256) {
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(userOpHash, userOp.signature);
        if (err != ECDSA.RecoverError.NoError || signer != owner[msg.sender]) return VALIDATION_FAILED;
        return VALIDATION_SUCCESS;
    }

    /// @dev ERC-1271 is deferred post-MVP.
    function isValidSignatureWithSender(address, bytes32, bytes calldata) external pure returns (bytes4) {
        return 0xffffffff;
    }
}
