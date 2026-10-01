// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WalletCore} from "./WalletCore.sol";
import {Module} from "./types/Module.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

interface IEntryPointSenderCreator {
    function senderCreator() external view returns (address);
}

contract WalletFactory {
    address public immutable implementation;
    address public immutable senderCreator;

    error NotSenderCreator();

    constructor(address entryPoint) {
        implementation = address(new WalletCore(entryPoint));
        senderCreator = IEntryPointSenderCreator(entryPoint).senderCreator();
    }

    /// @notice Deploys and initializes the account, or returns it if it already exists.
    function createAccount(
        address rootValidator,
        bytes calldata rootInitData,
        Module[] calldata extraModules,
        bytes32 salt
    ) external returns (address account) {
        if (msg.sender != senderCreator) revert NotSenderCreator();

        bytes32 accountSalt = _accountSalt(rootValidator, rootInitData, extraModules, salt);
        account = Clones.predictDeterministicAddress(implementation, accountSalt);
        if (account.code.length != 0) return account;

        Clones.cloneDeterministic(implementation, accountSalt);
        WalletCore(payable(account)).initialize(rootValidator, rootInitData, extraModules);
    }

    function getAddress(
        address rootValidator,
        bytes calldata rootInitData,
        Module[] calldata extraModules,
        bytes32 salt
    ) external view returns (address) {
        return Clones.predictDeterministicAddress(
            implementation, _accountSalt(rootValidator, rootInitData, extraModules, salt)
        );
    }

    function _accountSalt(
        address rootValidator,
        bytes calldata rootInitData,
        Module[] calldata extraModules,
        bytes32 salt
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(rootValidator, rootInitData, extraModules, salt));
    }
}
