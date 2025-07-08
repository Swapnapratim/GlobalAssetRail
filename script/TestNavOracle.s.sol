// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {NavOracle} from "../src/oracle/NavOracle.sol";
import {VaultManager} from "../src/vault/VaultManager.sol";

contract TestNavOracle is Script {
    // Deployed NavOracle address
    address constant NAV_ORACLE = 0x810F9678cB16b02FF88a92C5989aF45C426aa121;

    function run() public {
        uint256 deployerPrivateKey = uint256(
            0xdc22ea48d3b0de180b33a09a92402beed6d6db16a99d903fbd9c9515d5e5e6c2
        );
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Testing NavOracle at:", NAV_ORACLE);
        console.log("Deployer address:", deployer);

        vm.startBroadcast(deployer);

        NavOracle oracle = NavOracle(NAV_ORACLE);

        // Test performDailyUpdate function
        console.log("Calling performDailyUpdate...");
        oracle.performDailyUpdate();

        console.log("performDailyUpdate called successfully!");

        vm.stopBroadcast();

        // Log some additional info for verification
        console.log("=== NavOracle Info ===");
        // console.log("VaultManager:", oracle.vaultManager());
        // console.log("Subscription ID:", oracle.subscriptionId());
        // console.log("DON ID:", vm.toString(oracle.doId()));
        // console.log("Last Update Time:", oracle.lastUpdateTime());

        // Check registered assets by getting them from VaultManager
        VaultManager vault = VaultManager(oracle.vaultManager());
        console.log("=== Registered Assets ===");
        address[] memory assets = vault.getAssetList();
        for (uint i = 0; i < assets.length; i++) {
            console.log("Asset", i, ":", assets[i]);
            console.log("Asset Name:", oracle.assetKey(assets[i]));
        }

        console.log("=== Test Complete ===");
        console.log("If you see this message, the transaction was successful!");
        console.log(
            "Check the blockchain explorer for Chainlink Function execution details."
        );
    }
}
