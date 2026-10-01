// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC7579Module} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

contract MockModule is IERC7579Module {
    uint256 public immutable moduleType;
    mapping(address account => bytes data) public installData;
    mapping(address account => bytes data) public uninstallData;

    constructor(uint256 moduleType_) {
        moduleType = moduleType_;
    }

    function onInstall(bytes calldata data) external {
        installData[msg.sender] = data;
    }

    function onUninstall(bytes calldata data) external {
        delete installData[msg.sender];
        uninstallData[msg.sender] = data;
    }

    function isModuleType(uint256 moduleTypeId) external view returns (bool) {
        return moduleTypeId == moduleType;
    }
}
