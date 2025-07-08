// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {DepositOracle} from "../src/oracle/DepositOracle.sol";

contract DeployDepositOracle is Script {
    function run() external {
        address router = 0xf9B8fc078197181C841c296C876945aaa425B278;
        uint64 subscriptionId = 386;
        bytes32 donId = 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000;
        string
            memory depositSource = "const userAddress = args[0]; const assetsEncoded = args[1]; const amountsEncoded = args[2]; const assets = assetsEncoded.split(',').filter(addr => addr.length > 0); const amounts = amountsEncoded.split(',').filter(amt => amt.length > 0).map(amt => parseInt(amt)); const CUSTODY_API_BASE = 'https://gar-apis-akhgun4t8-sarvagnakadiyas-projects.vercel.app/'; const PROTOCOL_CUSTODY_ID = 'protocol_vault_001'; const holdingsRequest = Functions.makeHttpRequest({ url: `${CUSTODY_API_BASE}/verify-holdings`, method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + secrets.CUSTODY_API_KEY }, data: { institutionAddress: userAddress, assets: assets, amounts: amounts } }); const holdingsResponse = await holdingsRequest; if (holdingsResponse.error || !holdingsResponse.data.verified) { throw Error('Holdings verification failed: ' + (holdingsResponse.data?.message || 'Unknown error')); } const transferRequest = Functions.makeHttpRequest({ url: `${CUSTODY_API_BASE}/transfer-assets`, method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + secrets.CUSTODY_API_KEY }, data: { fromInstitution: userAddress, toProtocol: PROTOCOL_CUSTODY_ID, assets: assets, amounts: amounts, transferId: Functions.requestId } }); const transferResponse = await transferRequest; if (transferResponse.error || !transferResponse.data.success) { throw Error('Asset transfer failed: ' + (transferResponse.data?.message || 'Unknown error')); } const tokenizationRequest = Functions.makeHttpRequest({ url: `${CUSTODY_API_BASE}/mint-erc20`, method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + secrets.CUSTODY_API_KEY }, data: { protocolAddress: PROTOCOL_CUSTODY_ID, assets: assets, amounts: amounts, recipient: userAddress } }); const tokenizationResponse = await tokenizationRequest; if (tokenizationResponse.error || !tokenizationResponse.data.success) { throw Error('Tokenization failed: ' + (tokenizationResponse.data?.message || 'Unknown error')); } return Functions.encodeBytes(abi.encode(assets, amounts, userAddress));";

        address vaultManager = 0x39ee4747908925f7e52767Bd26CD602e8C50Ce62;

        vm.startBroadcast();
        DepositOracle depositOracle = new DepositOracle(
            router,
            subscriptionId,
            donId,
            depositSource,
            vaultManager
        );
        vm.stopBroadcast();

        console2.log("DepositOracle deployed at:", address(depositOracle));
    }
}
