Sarvagna Kadiya, [29 Jun 2025 at 7:56:46 PM]:
...// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {FunctionsClient} from "../../lib/chainlink/contracts/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import {FunctionsRequest} from "../../lib/chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {Strings} from "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {VaultManager} from "../vault/VaultManager.sol";
import {RoleManager} from "../onboarding/RoleManager.sol";

contract DepositOracle is FunctionsClient, RoleManager {
    using FunctionsRequest for FunctionsRequest.Request;

    uint64 public subscriptionId;
    bytes32 public donId;
    string public depositSource;

    VaultManager public vaultManager;
    mapping(bytes32 => address) public pendingRequests;
    mapping(bytes32 => address) public requestUser; // Track which user made the request

    event DepositRequested(bytes32 indexed requestId, address indexed user);
    event DepositFulfilled(
        bytes32 indexed requestId,
        address indexed user,
        address[] assets,
        uint256[] amounts
    );

    constructor(
        address _router,
        uint64 _subscriptionId,
        bytes32 _donId,
        string memory _depositSource,
        address _vaultManager
    ) FunctionsClient(_router) {
        subscriptionId = _subscriptionId;
        donId = _donId;
        depositSource = _depositSource;
        vaultManager = VaultManager(_vaultManager);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN, msg.sender);
    }

    function requestDeposit(
        address user,
        address[] calldata assets,
        uint256[] calldata amounts
    ) external returns (bytes32 requestId) {
        require(assets.length == amounts.length, "Arrays length mismatch");
        require(assets.length > 0, "Empty arrays");

        FunctionsRequest.Request memory req;
        req.initializeRequest(
            FunctionsRequest.Location.Inline,
            FunctionsRequest.CodeLanguage.JavaScript,
            depositSource
        );

        // Pass user address and asset/amount data to the function
        string[] memory args = new string[](3);
        args[0] = Strings.toHexString(uint160(user), 20);
        args[1] = _encodeAddressArray(assets);
        args[2] = _encodeUintArray(amounts);
        req.setArgs(args);

        requestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            300000,
            donId
        );

        pendingRequests[requestId] = user;
        requestUser[requestId] = user;
        emit DepositRequested(requestId, user);
    }

    function _fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (err.length > 0) {
            revert(string(err));
        }

        require(pendingRequests[requestId] != address(0), "Request not found");

        address user = pendingRequests[requestId];
        delete pendingRequests[requestId];
        delete requestUser[requestId];

        // Decode the response to get assets and amounts
        (address[] memory assets, uint256[] memory amounts) = abi.decode(
            response,
            (address[], uint256[])
        );

        // Call depositBatch on VaultManager
        // Note: This will fail if the user hasn't approved the tokens to this contract
        // In a real implementation, you might need to handle token approvals differently
        vaultManager.depositBatch(assets, amounts);

        emit DepositFulfilled(requestId, user, assets, amounts);
    }

    function _encodeAddressArray(
        address[] memory addresses
    ) internal pure returns (string memory) {
        bytes memory encoded = abi.encode(addresses);
        return Strings.toHexString(encoded);
    }

    function _encodeUintArray(
        uint256[] memory values
    ) internal pure returns (string memory) {
        bytes memory encoded = abi.encode(values);
        return Strings.toHexString(encoded);
    }

    function updateDepositSource(
            string memory _depositSource
        ) external onlyRole(ADMIN) {
            depositSource = _depositSource;
    }

    function setVaultManager(address _vaultManager) external onlyRole(ADMIN) {
        vaultManager = VaultManager(_vaultManager);
    }
}
