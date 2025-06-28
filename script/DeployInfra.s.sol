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
        registry = KYCRegistry(0x2A922A24A869Df0c745C9cE63B65D093dC57450d);

        KYCRegistry.InstitutionOnboardingData memory data = KYCRegistry.InstitutionOnboardingData({
            participant: 0x47C51d53D8B03062a308887a5f49ad9Ab0eA9688,
            delegetee: 0x47C51d53D8B03062a308887a5f49ad9Ab0eA9688,
            name: 'HDFC',
            signature: hex"535e6e573643eaee04ee9556232fabb154f3b70b615ecd5b9687d64d56415eab1d092493991ce23b692f01adf91e11ecf46fed94066397c151b98633467ea93e1c",
            timestampOfRegistration: 1751132243
        });
        registry.executeRegisterInstitution(data.participant, true, data);
        vm.stopBroadcast();
    }
}