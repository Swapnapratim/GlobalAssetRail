pragma solidity ^0.8.0;

import { AccessControl } from "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

contract FxOracle is AccessControl {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    
    // Target peg rate (18 decimals) - 1e18 = 1:1 peg
    uint256 public constant TARGET_PEG = 1e18;
    
    // Acceptable deviation (500 = 5%)
    uint256 public constant MAX_DEVIATION = 500;
    uint256 public constant BASIS_POINTS = 10000;

    // mapping of pair-hash → rate (18 decimals)
    mapping(bytes32 => uint256) public rates;
    
    // Track peg status
    mapping(bytes32 => bool) public isPegged;

    event RateUpdated(bytes32 indexed pairHash, uint256 rate, bool isPegged);
    event PegBroken(bytes32 indexed pairHash, uint256 rate, uint256 deviation);
    event PegRestored(bytes32 indexed pairHash, uint256 rate);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GOVERNOR_ROLE, msg.sender);
        
        // Initialize static 1:1 pegs for demo
        _setInitialPegs();
    }

    function setRate(string calldata from, string calldata to, uint256 rate) external onlyRole(GOVERNOR_ROLE) {
        bytes32 key = keccak256(abi.encodePacked(from, "/", to));
        rates[key] = rate;
        
        // Check peg status
        bool wasPegged = isPegged[key];
        bool nowPegged = _checkPeg(rate);
        isPegged[key] = nowPegged;
        
        emit RateUpdated(key, rate, nowPegged);
        
        // Emit peg events
        if (wasPegged && !nowPegged) {
            uint256 deviation = _calculateDeviation(rate);
            emit PegBroken(key, rate, deviation);
        } else if (!wasPegged && nowPegged) {
            emit PegRestored(key, rate);
        }
    }

    function getRate(string calldata from, string calldata to) external view returns (uint256) {
        return rates[keccak256(abi.encodePacked(from, "/", to))];
    }
    
    function checkPegStatus(string calldata from, string calldata to) external view returns (bool pegged, uint256 currentRate, uint256 deviation) {
        bytes32 key = keccak256(abi.encodePacked(from, "/", to));
        currentRate = rates[key];
        pegged = isPegged[key];
        deviation = _calculateDeviation(currentRate);
    }
    
    function _checkPeg(uint256 rate) internal pure returns (bool) {
        if (rate == 0) return false;
        
        uint256 deviation = _calculateDeviation(rate);
        return deviation <= MAX_DEVIATION;
    }
    
    function _calculateDeviation(uint256 rate) internal pure returns (uint256) {
        if (rate == 0) return BASIS_POINTS;
        
        uint256 diff = rate > TARGET_PEG ? rate - TARGET_PEG : TARGET_PEG - rate;
        return (diff * BASIS_POINTS) / TARGET_PEG;
    }
    
    function _setInitialPegs() internal {
        // Keep existing 1:1 local pegs
        bytes32 sINR_INR = keccak256(abi.encodePacked("sINR", "/", "INR"));
        bytes32 sUSD_USD = keccak256(abi.encodePacked("sUSD", "/", "USD"));
        bytes32 sYEN_YEN = keccak256(abi.encodePacked("sYEN", "/", "YEN"));
        
        rates[sINR_INR] = TARGET_PEG;
        rates[sUSD_USD] = TARGET_PEG; 
        rates[sYEN_YEN] = TARGET_PEG;
        
        // ADD: Cross-currency rates (all vs USD as base)
        bytes32 INR_USD = keccak256(abi.encodePacked("INR", "/", "USD"));
        bytes32 YEN_USD = keccak256(abi.encodePacked("YEN", "/", "USD"));
        
        rates[INR_USD] = 83e18;  // 1 USD = 83 INR
        rates[YEN_USD] = 150e18; // 1 USD = 150 YEN
        
        isPegged[sINR_INR] = true;
        isPegged[sUSD_USD] = true;
        isPegged[sYEN_YEN] = true;
    }
}
