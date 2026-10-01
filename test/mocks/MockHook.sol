// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC7579Hook, MODULE_TYPE_HOOK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

contract MockHook is IERC7579Hook {
    error PreCheckRejected();
    error PostCheckRejected();

    bool public rejectPreCheck;
    bool public rejectPostCheck;
    uint256 public preCheckCount;
    address public lastMsgSender;
    uint256 public lastMsgValue;
    bytes public lastMsgData;
    bytes public lastHookData;

    function setRejections(bool pre, bool post) external {
        rejectPreCheck = pre;
        rejectPostCheck = post;
    }

    function onInstall(bytes calldata) external {}

    function onUninstall(bytes calldata) external {}

    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_HOOK;
    }

    function preCheck(address msgSender, uint256 msgValue, bytes calldata msgData) external returns (bytes memory) {
        if (rejectPreCheck) revert PreCheckRejected();
        ++preCheckCount;
        lastMsgSender = msgSender;
        lastMsgValue = msgValue;
        lastMsgData = msgData;
        return abi.encode(preCheckCount);
    }

    function postCheck(bytes calldata hookData) external {
        if (rejectPostCheck) revert PostCheckRejected();
        lastHookData = hookData;
    }
}
