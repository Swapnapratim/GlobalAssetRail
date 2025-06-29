// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {StableToken} from "../src/token/StableToken.sol";

contract DeployStableToken is Script {
    function run() external {
        string memory name = "Stable INR";
        string memory symbol = "sINR";
        uint8 decimals = 18;
        address vaultManager = 0x39ee4747908925f7e52767Bd26CD602e8C50Ce62;

        vm.startBroadcast();
        StableToken stableToken = new StableToken(
            name,
            symbol,
            decimals,
            vaultManager
        );
        vm.stopBroadcast();

        console2.log("StableToken deployed at:", address(stableToken));
    }
}
