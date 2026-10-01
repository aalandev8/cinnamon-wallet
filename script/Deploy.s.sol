// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WalletFactory} from "../src/WalletFactory.sol";
import {ECDSAValidator} from "../src/modules/ECDSAValidator.sol";
import {SpendingLimitHook} from "../src/modules/SpendingLimitHook.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {Script} from "forge-std/Script.sol";

/// @notice Deploys the MVP contracts. Deploys a fresh EntryPoint 0.8 when ENTRY_POINT is unset (local chains).
contract Deploy is Script {
    function run() external {
        address entryPoint = vm.envOr("ENTRY_POINT", address(0));

        vm.startBroadcast();
        if (entryPoint == address(0)) entryPoint = address(new EntryPoint());
        WalletFactory factory = new WalletFactory(entryPoint);
        ECDSAValidator validator = new ECDSAValidator();
        SpendingLimitHook hook = new SpendingLimitHook();
        vm.stopBroadcast();

        string memory json = "deployment";
        vm.serializeAddress(json, "entryPoint", entryPoint);
        vm.serializeAddress(json, "factory", address(factory));
        vm.serializeAddress(json, "ecdsaValidator", address(validator));
        string memory output = vm.serializeAddress(json, "spendingLimitHook", address(hook));
        vm.writeJson(output, vm.envOr("DEPLOYMENT_FILE", string("e2e/deployments/local.json")));
    }
}
