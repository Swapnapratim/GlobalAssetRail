// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {FunctionsClient} from "../../lib/chainlink/contracts/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import {FunctionsRequest} from "../../lib/chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {Strings} from "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {VaultManager} from "../vault/VaultManager.sol";
import {RoleManager} from "../onboarding/RoleManager.sol";

contract NavOracle is FunctionsClient, RoleManager {
    using FunctionsRequest for FunctionsRequest.Request;

    uint64 public subscriptionId;
    bytes32 public donId;
    string public source;
    string public yieldSource;

    VaultManager public vaultManager;
    mapping(address => string) public assetKey;
    mapping(bytes32 => address) public pendingRequests;
    mapping(bytes32 => bool) public isYieldRequest;

    // For automation
    uint256 public lastUpdateTime;
    uint256 public constant UPDATE_INTERVAL = 30 minutes;

    event PriceRequested(bytes32 indexed requestId, address indexed asset);
    event PriceFulfilled(
        bytes32 indexed requestId,
        address indexed asset,
        uint256 price
    );
    event YieldRequested(bytes32 indexed requestId);
    event YieldFulfilled(bytes32 indexed requestId, uint256 totalYield);

    constructor(
        address _router,
        uint64 _subscriptionId,
        bytes32 _donId,
        string memory _source,
        string memory _yieldSource,
        address _vaultManager
    ) FunctionsClient(_router) {
        subscriptionId = _subscriptionId;
        donId = _donId;
        source = _source;
        yieldSource = _yieldSource;
        vaultManager = VaultManager(_vaultManager);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN, msg.sender);
        lastUpdateTime = block.timestamp;
    }

    function addAsset(
        address asset,
        string calldata key
    ) external onlyRole(ADMIN) {
        assetKey[asset] = key;
    }

    function performDailyUpdate() public {
        address[] memory assets = vaultManager.getAssetList();
        for (uint i = 0; i < assets.length; i++) {
            if (bytes(assetKey[assets[i]]).length > 0) {
                requestAssetPrice(assets[i]);
            }
        }

        // Update yields
        requestYieldUpdate();

        lastUpdateTime = block.timestamp;
    }

    function requestAssetPrice(
        address asset
    ) public returns (bytes32 requestId) {
        require(bytes(assetKey[asset]).length > 0, "Asset not registered");

        FunctionsRequest.Request memory req;
        req.initializeRequest(
            FunctionsRequest.Location.Inline,
            FunctionsRequest.CodeLanguage.JavaScript,
            source
        );

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

    function requestYieldUpdate() public returns (bytes32 requestId) {
        require(bytes(yieldSource).length > 0, "Yield source not set");

        FunctionsRequest.Request memory req;
        req.initializeRequest(
            FunctionsRequest.Location.Inline,
            FunctionsRequest.CodeLanguage.JavaScript,
            yieldSource
        );

        // Provide a dummy argument to avoid EmptyArgs error
        string[] memory args = new string[](1);
        args[0] = "dummy"; // Dummy argument that the yield function can ignore
        req.setArgs(args);

        requestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            300000,
            donId
        );

        isYieldRequest[requestId] = true;
        emit YieldRequested(requestId);
    }

    function updateAllAssetPrices() external {
        require(
            block.timestamp >= lastUpdateTime + UPDATE_INTERVAL,
            "Too early for update"
        );

        address[] memory assets = vaultManager.getAssetList();
        for (uint i = 0; i < assets.length; i++) {
            if (bytes(assetKey[assets[i]]).length > 0) {
                requestAssetPrice(assets[i]);
            }
        }
        lastUpdateTime = block.timestamp;
    }

    function _fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (err.length > 0) {
            revert(string(err));
        }

        if (isYieldRequest[requestId]) {
            delete isYieldRequest[requestId];
            uint256 totalYield = abi.decode(response, (uint256));

            if (totalYield > 0) {
                vaultManager.recordAccruedYield(totalYield);
            }

            emit YieldFulfilled(requestId, totalYield);
        } else {
            require(
                pendingRequests[requestId] != address(0),
                "Request not found"
            );

            address asset = pendingRequests[requestId];
            delete pendingRequests[requestId];

            uint256 price = abi.decode(response, (uint256));
            uint256 navPerToken = price * 1e18;

            vaultManager.updateAssetNav(asset, navPerToken);
            emit PriceFulfilled(requestId, asset, price);
        }
    }

    function updateSource(string memory _source) external onlyRole(ADMIN) {
        source = _source;
    }

    function setVaultManager(address _vaultManager) external onlyRole(ADMIN) {
        vaultManager = VaultManager(_vaultManager);
    }
}
