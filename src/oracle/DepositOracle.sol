// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import { FunctionsClient } from "../../lib/chainlink/contracts/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import { FunctionsRequest } from "../../lib/chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import { VaultManager } from "../vault/VaultManager.sol";

contract DepositOracle is FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    VaultManager public vaultManager;
    address public protocolOwner;
    uint64 public subscriptionId;
    bytes32 public donId;
    string public source;
    
    mapping(bytes32 => string) public pendingRequests;
    mapping(string => DepositData) public depositDetails;

    struct DepositData {
        address institution;
        address assetAddress;
        uint256 amount;
        bool processed;
    }

    event DepositInitiated(string indexed depositId, bytes32 indexed requestId);
    event DepositCompleted(string indexed depositId);
    event DepositFailed(string indexed depositId, string reason);
    
    modifier onlyProtocol() {
        require(msg.sender == protocolOwner, "ONLY_PROTOCOL");
        _;
    }

    constructor(
        address _router,
        address _vaultManager,
        address _protocolOwner,
        uint64 _subscriptionId,
        bytes32 _donId,
        string memory _source
    ) FunctionsClient(_router) {
        vaultManager = VaultManager(_vaultManager);
        protocolOwner = _protocolOwner;
        subscriptionId = _subscriptionId;
        donId = _donId;
        source = _source;
    }
    
    function processDeposit(string calldata depositId) external onlyProtocol returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req.initializeRequest(FunctionsRequest.Location.Inline, FunctionsRequest.CodeLanguage.JavaScript, source);
        
        string[] memory args = new string[](1);
        args[0] = depositId;
        req.setArgs(args);

        requestId = _sendRequest(req.encodeCBOR(), subscriptionId, 300000, donId);
        pendingRequests[requestId] = depositId;
        
        emit DepositInitiated(depositId, requestId);
    }
    
    function _fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        string memory depositId = pendingRequests[requestId];
        delete pendingRequests[requestId];

        if (err.length > 0) {
            emit DepositFailed(depositId, string(err));
            return;
        }

        string memory status = string(response);
        
        if (keccak256(bytes(status)) == keccak256(bytes("OK"))) {
            _executeOnChainDeposit(depositId);
            emit DepositCompleted(depositId);
        } else {
            emit DepositFailed(depositId, status);
        }
    }
    
    function _executeOnChainDeposit(string memory depositId) internal {
        DepositData memory deposit = depositDetails[depositId];
        require(!deposit.processed, "Deposit already processed");
        require(deposit.institution != address(0), "Invalid deposit data");
        
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        
        assets[0] = deposit.assetAddress;
        amounts[0] = deposit.amount;
        
        depositDetails[depositId].processed = true;
        
        vaultManager.depositBatch(assets, amounts);
    }

    function setDepositData(
        string calldata depositId,
        address institution,
        address assetAddress,
        uint256 amount
    ) external onlyProtocol {
        depositDetails[depositId] = DepositData({
            institution: institution,
            assetAddress: assetAddress,
            amount: amount,
            processed: false
        });
    }
}
