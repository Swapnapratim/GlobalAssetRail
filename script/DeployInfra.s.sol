// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import { KYCRegistry } from "../src/onboarding/KYCRegistry.sol"; 

contract DeployInfra is Script {
    address private deployer;
    KYCRegistry public registry;

    function run() public {
        uint256 deployerPrivateKey = uint256(0xdc22ea48d3b0de180b33a09a92402beed6d6db16a99d903fbd9c9515d5e5e6c2);
        deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployer);
        registry = new KYCRegistry();
        vm.stopBroadcast();
    }
}