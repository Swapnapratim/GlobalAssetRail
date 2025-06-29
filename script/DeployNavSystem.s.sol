// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import { VaultManager } from "../src/vault/VaultManager.sol";
import { NavOracle } from "../src/oracle/NavOracle.sol";
import { IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DeployNavSystem is Script {
    // Chainlink Functions config for Base Sepolia
    address constant FUNCTIONS_ROUTER = 0xf9B8fc078197181C841c296C876945aaa425B278;
    uint64 constant SUBSCRIPTION_ID = 386; 
    bytes32 constant DON_ID = 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000;
    
    // Import the source from your functions file
    string constant SOURCE = "const assetAddress = args[0] || '0xbDcfBEd3188040926bbEaBD70a25cFbE081F428d'; const CUSTODY_API = 'https://gar-apis-akhgun4t8-sarvagnakadiyas-projects.vercel.app'; const custodyRequest = Functions.makeHttpRequest({ url: `${CUSTODY_API}/getAssetPrice`, method: 'POST', headers: { 'Content-Type': 'application/json' }, data: { assetAddress } }); const response = await custodyRequest; if (response.error) { throw Error('Request failed'); } const price = response.data.price; return Functions.encodeUint256(price);";
    string constant YIELD_SOURCE = "const CUSTODY_API = 'https://gar-apis-akhgun4t8-sarvagnakadiyas-projects.vercel.app'; const response = await Functions.makeHttpRequest({ url: `${CUSTODY_API}/getTotalYield`, method: 'GET', headers: { 'Content-Type': 'application/json' } }); if (response.error) throw Error('Yield request failed'); return Functions.encodeUint256(response.data.totalYield);";
    function run() public {
        uint256 deployerPrivateKey = uint256(0xdc22ea48d3b0de180b33a09a92402beed6d6db16a99d903fbd9c9515d5e5e6c2);
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployer);
        
        // Deploy VaultManager
        VaultManager vault = VaultManager(0x39ee4747908925f7e52767Bd26CD602e8C50Ce62);
        
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
        
        vault.addAsset(0x3dbb0344f6C2Fe6122179Cc3795A3eB10Be458dc, 500);  // INR-SGB
        vault.addAsset(0x50F3660D13E12eb9cAb75df95305B404E6d2d506, 1000); // INR-CORP
        vault.addAsset(0x69617a40EA29Aabc6BCd151865cfC62e30b67012, 200);  // INR-MFD
        
        // Register assets in oracle
        oracle.addAsset(0x3dbb0344f6C2Fe6122179Cc3795A3eB10Be458dc, "INR-SGB");
        oracle.addAsset(0x50F3660D13E12eb9cAb75df95305B404E6d2d506, "INR-CORP");
        oracle.addAsset(0x69617a40EA29Aabc6BCd151865cfC62e30b67012, "INR-MFD");
        
        vm.stopBroadcast();
        
        console.log("VaultManager deployed at:", address(vault));
        console.log("NavOracle deployed at:", address(oracle));
    }
}
