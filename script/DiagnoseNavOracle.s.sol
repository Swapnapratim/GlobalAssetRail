// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {NavOracle} from "../src/oracle/NavOracle.sol";
import {VaultManager} from "../src/vault/VaultManager.sol";

contract DiagnoseNavOracle is Script {
    // Deployed NavOracle address
    address constant NAV_ORACLE = 0xdE4A516f29339089c21B79DFD40a7f50D22414c9;

    function run() public {
        console.log("=== NavOracle Diagnosis ===");

        NavOracle oracle = NavOracle(NAV_ORACLE);

        // Check basic contract info
        console.log("NavOracle address:", NAV_ORACLE);
        console.log("VaultManager:", oracle.vaultManager());
        console.log("Subscription ID:", oracle.subscriptionId());
        console.log("DON ID:", vm.toString(oracle.donId()));
        console.log("Last Update Time:", oracle.lastUpdateTime());

        // Check VaultManager assets
        VaultManager vault = VaultManager(oracle.vaultManager());
        address[] memory assets = vault.getAssetList();
        console.log("Number of assets in vault:", assets.length);

        for (uint i = 0; i < assets.length; i++) {
            console.log("Asset", i, ":", assets[i]);
            console.log(
                "Asset registered in oracle:",
                oracle.assetKey(assets[i])
            );
        }

        // Check if assets are properly registered
        console.log("\n=== Asset Registration Check ===");
        for (uint i = 0; i < assets.length; i++) {
            string memory assetKey = oracle.assetKey(assets[i]);
            if (bytes(assetKey).length > 0) {
                console.log(
                    "✅ Asset",
                    assets[i],
                    "is registered as:",
                    assetKey
                );
            } else {
                console.log(
                    "❌ Asset",
                    assets[i],
                    "is NOT registered in oracle"
                );
            }
        }

        // Check source code
        console.log("\n=== Source Code Check ===");
        string memory source = oracle.source();
        console.log("Source code length:", bytes(source).length);
        if (bytes(source).length > 0) {
            console.log("✅ Source code is set");
        } else {
            console.log("❌ Source code is empty");
        }

        string memory yieldSource = oracle.yieldSource();
        console.log("Yield source length:", bytes(yieldSource).length);
        if (bytes(yieldSource).length > 0) {
            console.log("✅ Yield source is set");
        } else {
            console.log("❌ Yield source is empty");
        }

        console.log("\n=== Recommendations ===");
        console.log("1. Check if subscription 386 has sufficient LINK balance");
        console.log("2. Verify subscription 386 is active and not paused");
        console.log("3. Check if the API endpoint is accessible");
        console.log("4. Verify the source code format is correct");
    }
}
