// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import { VaultManager } from "../src/vault/VaultManager.sol";
import { NavOracle } from "../src/oracle/NavOracle.sol";
import { IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DeployNavSystem is Script {
    // Chainlink Functions config for Base Sepolia
    address constant FUNCTIONS_ROUTER = 0xf9B8fc078197181C841c296C876945aaa425B278;
    uint64 constant SUBSCRIPTION_ID = 1; // Replace with your subscription ID
    bytes32 constant DON_ID = 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000;
    
    // Import the source from your functions file
    string constant SOURCE = "const assetAddress = args[0] || '0xbDcfBEd3188040926bbEaBD70a25cFbE081F428d'; const CUSTODY_API = 'https://-api.com'; const custodyRequest = Functions.makeHttpRequest({ url: `${CUSTODY_API}/getAssetPrice`, method: 'POST', headers: { 'Content-Type': 'application/json' }, data: { assetAddress } }); const response = await custodyRequest; if (response.error) { throw Error('Request failed'); } const price = response.data.price; return Functions.encodeUint256(price);";
    string constant YIELD_SOURCE = "const CUSTODY_API = 'https://api.com'; const response = await Functions.makeHttpRequest({ url: `${CUSTODY_API}/getTotalYield`, method: 'GET', headers: { 'Content-Type': 'application/json' } }); if (response.error) throw Error('Yield request failed'); return Functions.encodeUint256(response.data.totalYield);";
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployer);
        
        // Deploy dummy ERC20 for vault (you can use address(0) for now)
        IERC20 dummyToken = IERC20(address(0));
        
        // Deploy VaultManager
        VaultManager vault = new VaultManager(
            dummyToken,
            "Global Asset Rail Vault",
            "GAR"
        );
        
        // Deploy NavOracle
        NavOracle oracle = new NavOracle(
            FUNCTIONS_ROUTER,
            SUBSCRIPTION_ID,
            DON_ID,
            SOURCE,
            YIELD_SOURCE,
            address(vault)
        );
        
        // Grant SENTINEL role to oracle
        vault.grantSentinelRole(address(oracle));
        
        vault.addAsset(0xbDcfBEd3188040926bbEaBD70a25cFbE081F428d, 500);  // INR-SGB
        vault.addAsset(0x4F1F27A247a11b41D85c1D9B22304D8DAB8ae736, 1000); // INR-CORP
        vault.addAsset(0x40fA3ffdefa6613680F98F75771b897F8020cdF7, 200);  // INR-MFD
        
        // Register assets in oracle
        oracle.addAsset(0xbDcfBEd3188040926bbEaBD70a25cFbE081F428d, "INR-SGB");
        oracle.addAsset(0x4F1F27A247a11b41D85c1D9B22304D8DAB8ae736, "INR-CORP");
        oracle.addAsset(0x40fA3ffdefa6613680F98F75771b897F8020cdF7, "INR-MFD");
        
        vm.stopBroadcast();
        
        console.log("VaultManager deployed at:", address(vault));
        console.log("NavOracle deployed at:", address(oracle));
    }
}
