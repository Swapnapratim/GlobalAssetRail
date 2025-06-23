// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { FunctionsClient } from "../../lib/chainlink/contracts/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import { FunctionsRequest } from "../../lib/chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import { Strings } from "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract NavOracle is FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    uint64 public subscriptionId;
    bytes32 public donId;
    string public source;
    
    mapping(address => string) public assetKey;
    mapping(bytes32 => address) public pendingRequests;

    event PriceRequested(bytes32 indexed requestId, address indexed asset);
    event PriceFulfilled(bytes32 indexed requestId, address indexed asset, uint256 price);

    constructor(
        address _router,
        uint64 _subscriptionId,
        bytes32 _donId,
        string memory _source
    ) FunctionsClient(_router) {
        subscriptionId = _subscriptionId;
        donId = _donId;
        source = _source;
    }

    function addAsset(address asset, string calldata key) external {
        assetKey[asset] = key;
    }

    function requestAssetPrice(address asset) external returns (bytes32 requestId) {
        require(bytes(assetKey[asset]).length > 0, "Asset not registered");

        FunctionsRequest.Request memory req;
        req.initializeRequest(FunctionsRequest.Location.Inline, FunctionsRequest.CodeLanguage.JavaScript, source);
        
        string[] memory args = new string[](1);
        args[0] = Strings.toHexString(uint160(asset), 20);
        req.setArgs(args);

        requestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            300000,
            donId
        );

        pendingRequests[requestId] = asset;
        emit PriceRequested(requestId, asset);
    }

    function _fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        require(pendingRequests[requestId] != address(0), "Request not found");
        
        address asset = pendingRequests[requestId];
        delete pendingRequests[requestId];

        if (err.length > 0) {
            revert(string(err));
        }

        uint256 price = abi.decode(response, (uint256));
        emit PriceFulfilled(requestId, asset, price);
    }

    function updateSource(string memory _source) external {
        source = _source;
    }
}
