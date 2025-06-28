// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import { ERC20Mock } from "./mocks/Mocks.sol";

contract DeployMockAssets is Script {
    address private deployer;
    ERC20Mock public inrGoldBond;
    ERC20Mock public inrCorpBond;
    ERC20Mock public inrMutualFund;
    function run() external {
        uint256 deployerPrivateKey = uint256(0xdc22ea48d3b0de180b33a09a92402beed6d6db16a99d903fbd9c9515d5e5e6c2);
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployer);
        inrGoldBond = new ERC20Mock("Indian Sovereign Gold Bond", "INR-SGB");
        inrCorpBond = new ERC20Mock("Indian Coroporate Bond", "INR-CORP");
        inrMutualFund = new ERC20Mock("Indian Mutual Fund", "INR-MFD"); 

        inrGoldBond.mint(deployer, 1000000e18);
        inrCorpBond.mint(deployer, 1000000e18);    
        inrMutualFund.mint(deployer, 1000000e18);

        vm.stopBroadcast(); 

        console.log("inrGoldBond: ", address(inrGoldBond));
        console.log("inrCorpBond: ", address(inrCorpBond));
        console.log("inrMutualFund: ", address(inrMutualFund));

    }
}