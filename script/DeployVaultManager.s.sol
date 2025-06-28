// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import { VaultManager } from "../src/vault/VaultManager.sol";
import { IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DeployVaultManager is Script {
    address private deployer;
    VaultManager public vaultManager;
    
    // Asset addresses
    address constant ASSET_1 = 0xbDcfBEd3188040926bbEaBD70a25cFbE081F428d; // INR-SGB
    address constant ASSET_2 = 0x4F1F27A247a11b41D85c1D9B22304D8DAB8ae736; // INR-CORP
    address constant ASSET_3 = 0x40fA3ffdefa6613680F98F75771b897F8020cdF7; // INR-MFD
    
    // Dummy token for ERC4626 requirement
    address constant DUMMY_TOKEN = address(0);

    function run() public {
        uint256 deployerPrivateKey = uint256(0xdc22ea48d3b0de180b33a09a92402beed6d6db16a99d903fbd9c9515d5e5e6c2);
        deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy VaultManager
        vaultManager = new VaultManager(
            IERC20(DUMMY_TOKEN),
            "India Vault",
            "IV"
        );
        
        console.log("VaultManager deployed at:", address(vaultManager));
        
        vaultManager.addAsset(ASSET_1, 500);  
        vaultManager.addAsset(ASSET_2, 1000);  
        vaultManager.addAsset(ASSET_3, 200);
        
        console.log("Added asset 1 (INR-SGB):", ASSET_1, "with 5% haircut");
        console.log("Added asset 2 (INR-CORP):", ASSET_2, "with 10% haircut");
        console.log("Added asset 3 (INR-MFD):", ASSET_3, "with 2% haircut");
        
        // Verify assets were added
        address[] memory assetList = vaultManager.getAssetList();
        console.log("Total assets added:", assetList.length);
        
        for (uint i = 0; i < assetList.length; i++) {
            console.log("Asset", i, ":", assetList[i]);
        }
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("VaultManager:", address(vaultManager));
        console.log("Deployer:", deployer);
        console.log("Assets configured: 3");
    }
}
