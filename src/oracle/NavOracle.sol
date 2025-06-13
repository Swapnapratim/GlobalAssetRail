// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Pausable } from "../../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { RoleManager } from "../onboarding/RoleManager.sol";

import { FunctionsClient } from "../../lib/chainlink/contracts/src/v0.8/functions/v1_3_0/FunctionsClient.sol";

/**
 * @title NavOracle
 * @notice Stores and manages NAV (Net Asset Value) data for collateral assets via Chainlink Functions
 * @dev - Receives NAV updates from off-chain Chainlink Functions for bonds, equities, gold, etc.
 *      - Implements staleness checks and fallback mechanisms
 *      - Supports multi-source aggregation with median calculation
 *      - Maintains historical NAV data for auditing and emergency fallbacks
 *      - Integrates with VaultManager for real-time collateral valuation
 */
contract NavOracle is RoleManager, Pausable, ReentrancyGuard, FunctionsClient {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant NAV_PRECISION = 1e18;
    uint256 public constant MAX_STALENESS = 24 hours;
    uint256 public constant MIN_STALENESS = 5 minutes;
    uint256 public constant MAX_DEVIATION = 1000; // 10% max deviation BP
    uint256 public constant BASIS_POINTS  = 10000;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct NavData {
        uint256 value;
        uint256 timestamp;
        uint256 blockNumber;
        bool    isActive;
        uint256 confidence;
    }

    struct SourceData {
        uint256 value;
        uint256 timestamp;
        bool    isValid;
        string  sourceName;
    }

    struct AssetConfig {
        string  name;
        string  currency;
        uint256 maxStaleness;
        uint256 minConfidence;
        bool    requiresMultiSource;
        uint8   decimals;
    }

    /*//////////////////////////////////////////////////////////////
                         CHAINLINK FUNCTIONS STATE
    //////////////////////////////////////////////////////////////*/
    uint64  public subscriptionId;
    address public oracleRouter;
    bytes32 public latestRequestId;

    mapping(bytes32 => bool)    public pendingRequests;
    mapping(bytes32 => address) public requestToAsset;

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/
    mapping(address => NavData)                      public assetNavData;
    mapping(address => AssetConfig)                  public assetConfigs;
    mapping(address => bool)                         public supportedAssets;
    address[]                                        public assetList;
    mapping(address => mapping(uint256 => SourceData)) public sourceData;
    mapping(address => uint256)                      public sourceCount;
    mapping(address => uint256[])                    public historicalNavs;
    mapping(address => bool)                         public authorizedSources;
    mapping(address => string)                       public sourceNames;

    uint256 public defaultStalenessThreshold = 1 hours;
    bool    public emergencyMode;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event NavUpdated(
        address indexed asset,
        uint256 oldValue,
        uint256 newValue,
        uint256 timestamp,
        uint256 confidence
    );
    event MultiSourceNavUpdated(
        address indexed asset,
        uint256[] sourceValues,
        uint256 aggregatedValue,
        uint256 timestamp
    );
    event AssetAdded(address indexed asset, string name, string currency, AssetConfig config);
    event EmergencyModeToggled(bool enabled, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyAuthorizedSource() {
        require(authorizedSources[msg.sender] || hasRole(SENTINEL, msg.sender), "NOT_AUTHORIZED_SOURCE");
        _;
    }
    modifier assetExists(address asset) {
        require(supportedAssets[asset], "ASSET_NOT_SUPPORTED");
        _;
    }
    modifier notEmergency() {
        require(!emergencyMode, "EMERGENCY_ACTIVE");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _router,
        address _link,
        uint64  _subId
    ) FunctionsClient(_link) {
        oracleRouter   = _router;
        subscriptionId = _subId;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN, msg.sender);
        _grantRole(SENTINEL, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                         CHAINLINK FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Request an off-chain NAV update via Chainlink Functions
     * @param assetKey Unique key for off-chain lookup
     * @param asset    On-chain asset address
     */
    function requestNavUpdate(
        string calldata assetKey,
        address        asset
    ) external onlyRole(PROTOCOL_CONTROLLER) returns (bytes32) {
        Functions.Request memory req;
        req = Functions.buildRequest(
            "fetchNav.js",
            abi.encode(assetKey)
        );
        bytes32 reqId = sendRequestTo(oracleRouter, req, subscriptionId);
        pendingRequests[reqId] = true;
        requestToAsset[reqId]  = asset;
        latestRequestId        = reqId;
        return reqId;
    }

    /**
     * @dev Callback from Chainlink Functions
     */
    function fulfillRequest(
        bytes32        requestId,
        bytes memory   response,
        bytes memory   /*err*/
    ) internal override {
        require(pendingRequests[requestId], "Unknown request");
        delete pendingRequests[requestId];
        address asset = requestToAsset[requestId];
        uint256 newNav = abi.decode(response, (uint256));
        updateNav(asset, newNav, BASIS_POINTS);
    }

    /*//////////////////////////////////////////////////////////////
                        ASSET MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    function addAsset(address asset, AssetConfig memory config) external onlyRole(ADMIN) {
        require(asset != address(0), "INVALID_ASSET");
        require(!supportedAssets[asset], "ALREADY_EXISTS");
        require(
            config.maxStaleness >= MIN_STALENESS && config.maxStaleness <= MAX_STALENESS,
            "BAD_STALENESS"
        );
        require(config.minConfidence <= BASIS_POINTS, "BAD_CONFIDENCE");

        supportedAssets[asset] = true;
        assetConfigs[asset]    = config;
        assetList.push(asset);

        assetNavData[asset] = NavData({
            value: NAV_PRECISION,
            timestamp: block.timestamp,
            blockNumber: block.number,
            isActive: true,
            confidence: BASIS_POINTS
        });

        emit AssetAdded(asset, config.name, config.currency, config);
    }

    /*//////////////////////////////////////////////////////////////
                        NAV UPDATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function updateNav(
        address asset,
        uint256 newNav,
        uint256 confidence
    ) public nonReentrant whenNotPaused onlyAuthorizedSource assetExists(asset) notEmergency {
        require(newNav > 0, "INVALID_NAV");
        require(confidence <= BASIS_POINTS, "BAD_CONF");

        NavData storage navData   = assetNavData[asset];
        AssetConfig storage config = assetConfigs[asset];
        require(confidence >= config.minConfidence, "LOW_CONF");

        // record history
        historicalNavs[asset].push(navData.value);
        if (historicalNavs[asset].length > 100) historicalNavs[asset].pop();

        uint256 oldValue = navData.value;
        navData.value       = newNav;
        navData.timestamp   = block.timestamp;
        navData.blockNumber = block.number;
        navData.confidence  = confidence;

        emit NavUpdated(asset, oldValue, newNav, block.timestamp, confidence);
    }

    function updateNavMultiSource(
        address        asset,
        uint256[] calldata sourceValues,
        uint256[] calldata sourceIndices
    ) external nonReentrant whenNotPaused onlyAuthorizedSource assetExists(asset) notEmergency {
        uint256 count = sourceValues.length;
        require(count == sourceIndices.length && count > 0, "BAD_ARRAYS");

        AssetConfig storage config = assetConfigs[asset];
        require(
            !config.requiresMultiSource || count >= 2,
            "INSUFFICIENT_SRC"
        );

        for (uint256 i = 0; i < count; i++) {
            require(sourceValues[i] > 0, "ZERO_SRC");
            sourceData[asset][sourceIndices[i]] = SourceData({
                value: sourceValues[i],
                timestamp: block.timestamp,
                isValid: true,
                sourceName: sourceNames[msg.sender]
            });
        }

        uint256 aggregated = _calculateMedian(sourceValues);
        if (count > 1) {
            uint256 dev = _calculateMaxDeviation(sourceValues, aggregated);
            require(dev <= MAX_DEVIATION, "DEVIATION_TOO_HIGH");
        }

        NavData storage navData = assetNavData[asset];
        uint256 oldValue = navData.value;

        navData.value       = aggregated;
        navData.timestamp   = block.timestamp;
        navData.blockNumber = block.number;
        navData.confidence  = BASIS_POINTS;

        historicalNavs[asset].push(oldValue);

        emit MultiSourceNavUpdated(asset, sourceValues, aggregated, block.timestamp);
        emit NavUpdated(asset, oldValue, aggregated, block.timestamp, BASIS_POINTS);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW & UTILITY
    //////////////////////////////////////////////////////////////*/
    function getNav(address asset) external view returns (uint256 nav, uint256 ts, bool stale) {
        require(supportedAssets[asset], "NOT_SUPPORTED");
        NavData storage d = assetNavData[asset];
        nav   = d.value;
        ts    = d.timestamp;
        stale = (block.timestamp - ts) > assetConfigs[asset].maxStaleness;
    }

    function _calculateMedian(uint256[] calldata arr) internal pure returns (uint256) {
        uint256 len = arr.length;
        uint256[] memory vals = new uint256[](len);
        for (uint256 i = 0; i < len; i++) vals[i] = arr[i];
        // selection sort
        for (uint256 i = 0; i < len; i++) {
            uint256 minIdx = i;
            for (uint256 j = i + 1; j < len; j++) {
                if (vals[j] < vals[minIdx]) minIdx = j;
            }
            (vals[i], vals[minIdx]) = (vals[minIdx], vals[i]);
        }
        uint256 mid = len / 2;
        if (len % 2 == 1) {
            return vals[mid];
        }
        return (vals[mid - 1] + vals[mid]) / 2;
    }

    function _calculateMaxDeviation(
        uint256[] calldata arr,
        uint256 aggregated
    ) internal pure returns (uint256 maxDev) {
        for (uint256 i = 0; i < arr.length; i++) {
            uint256 diff = arr[i] > aggregated ? arr[i] - aggregated : aggregated - arr[i];
            uint256 bp   = (diff * BASIS_POINTS) / aggregated;
            if (bp > maxDev) maxDev = bp;
        }
    }

    /* Emergency controls omitted for brevity */
}
