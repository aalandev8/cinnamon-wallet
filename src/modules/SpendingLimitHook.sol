// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CallType, ERC7579Utils, Mode} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {
    Execution,
    IERC7579Execution,
    IERC7579Hook,
    MODULE_TYPE_HOOK
} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

/// @notice Native ETH daily spending limit. Storage is keyed by the calling account.
contract SpendingLimitHook is IERC7579Hook {
    mapping(address account => uint256) public limit;
    mapping(address account => uint256) public epoch;
    mapping(address account => uint256) public spent;
    mapping(address account => bool) public isInitialized;

    error AlreadyInstalled(address account);
    error NotInitialized(address account);
    error DailyLimitExceeded(uint256 spent, uint256 limit);

    function onInstall(bytes calldata data) external {
        if (isInitialized[msg.sender]) revert AlreadyInstalled(msg.sender);
        isInitialized[msg.sender] = true;
        limit[msg.sender] = abi.decode(data, (uint256));
    }

    function onUninstall(bytes calldata) external {
        delete isInitialized[msg.sender];
        delete limit[msg.sender];
        delete epoch[msg.sender];
        delete spent[msg.sender];
    }

    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_HOOK;
    }

    function setLimit(uint256 newLimit) external {
        if (!isInitialized[msg.sender]) revert NotInitialized(msg.sender);
        limit[msg.sender] = newLimit;
    }

    /// @dev Spend is decoded from `msgData`: under the EntryPoint `msgValue` is always zero.
    function preCheck(address, uint256, bytes calldata msgData) external returns (bytes memory) {
        uint256 value = _spendOf(msgData);
        if (value == 0) return "";

        uint256 currentEpoch = block.timestamp / 1 days;
        uint256 total = epoch[msg.sender] == currentEpoch ? spent[msg.sender] + value : value;
        if (total > limit[msg.sender]) revert DailyLimitExceeded(total, limit[msg.sender]);

        epoch[msg.sender] = currentEpoch;
        spent[msg.sender] = total;
        return "";
    }

    function postCheck(bytes calldata) external {}

    function _spendOf(bytes calldata msgData) private pure returns (uint256 value) {
        if (msgData.length < 4) return 0;
        bytes4 selector = bytes4(msgData);
        if (
            selector != IERC7579Execution.execute.selector && selector != IERC7579Execution.executeFromExecutor.selector
        ) {
            return 0;
        }

        (CallType callType,,,) = ERC7579Utils.decodeMode(Mode.wrap(bytes32(msgData[4:36])));
        bytes calldata executionCalldata = _bytesArg(msgData, 36);

        if (callType == ERC7579Utils.CALLTYPE_SINGLE) {
            (, value,) = ERC7579Utils.decodeSingle(executionCalldata);
        } else if (callType == ERC7579Utils.CALLTYPE_BATCH) {
            Execution[] calldata batch = ERC7579Utils.decodeBatch(executionCalldata);
            for (uint256 i; i < batch.length; ++i) {
                value += batch[i].value;
            }
        }
    }

    /// @dev Resolves the ABI head word at `headPos` into a calldata slice of the dynamic `bytes` it points to.
    function _bytesArg(bytes calldata msgData, uint256 headPos) private pure returns (bytes calldata) {
        uint256 start = 4 + uint256(bytes32(msgData[headPos:headPos + 32]));
        uint256 length = uint256(bytes32(msgData[start:start + 32]));
        return msgData[start + 32:start + 32 + length];
    }
}
