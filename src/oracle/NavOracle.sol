// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { FunctionsClient } from "../../lib/chainlink/contracts/src/v0.8/functions/v1_3_0/FunctionsClient.sol";
import { KeeperCompatibleInterface } from "../../lib/chainlink/contracts/src/v0.8/automation/interfaces/KeeperCompatibleInterface.sol";
import { RoleManager } from "../onboarding/RoleManager.sol";
import { VaultManager } from "../vault/VaultManager.sol";

/// @notice PoC NavOracle + Keeper scheduling + Chainlink Functions
contract NavOracle is FunctionsClient, KeeperCompatibleInterface, RoleManager {
    uint64   public subscriptionId;
    address  public router;
    address  public vault;
    uint256  public lastUpkeep;
    uint256  public interval = 24 hours;

    address[] public assets;
    mapping(address=>string) public assetKey;
    struct Req { address asset; bool isYield; }
    mapping(bytes32=>Req) public pending;

    event Requested(bytes32 indexed id, address indexed asset, bool isYield);
    event Fulfilled(bytes32 indexed id, address indexed asset, bool isYield, uint256 value);

    constructor(address _link, address _router, uint64 _subId, address _vault)
      FunctionsClient(_link)
    {
        subscriptionId = _subId;
        router         = _router;
        vault          = _vault;
        lastUpkeep     = block.timestamp;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN, msg.sender);
    }

    /// @notice Register a new collateral asset and its lookup key
    function addAsset(address a, string calldata key) external onlyRole(ADMIN) {
        assets.push(a);
        assetKey[a] = key;
    }

    /// @dev Called by Chainlink Automation every `interval`
    function checkUpkeep(bytes calldata) external view override
      returns (bool upkeepNeeded, bytes memory)
    {
        upkeepNeeded = (block.timestamp - lastUpkeep) >= interval;
    }

    function performUpkeep(bytes calldata) external override {
        require(block.timestamp - lastUpkeep >= interval, "NavOracle: Too soon");
        for (uint i = 0; i < assets.length; i++) {
            _request(assets[i], false);  // price/nav
            _request(assets[i], true);   // yield
        }
        lastUpkeep = block.timestamp;
    }

    function _request(address asset, bool isYield) internal {
        bytes32 id = sendRequestTo(
            router,
            Functions.buildRequest("fetchNav.js", abi.encode(assetKey[asset], isYield)),
            subscriptionId
        );
        pending[id] = Req(asset, isYield);
        emit Requested(id, asset, isYield);
    }

    /// @dev Chainlink Functions callback
    function fulfillRequest(
        bytes32 id,
        bytes memory response,
        bytes memory
    ) internal override {
        Req memory r = pending[id];
        delete pending[id];

        uint256 val = abi.decode(response, (uint256));

        if (r.isYield) {
            // credit coupons/dividends into vault
            VaultManager(vault).recordAccruedYield(val);
        } else {
            // update on-chain NAV per token
            VaultManager(vault).updateAssetNav(r.asset, val);
        }

        emit Fulfilled(id, r.asset, r.isYield, val);
    }
}
