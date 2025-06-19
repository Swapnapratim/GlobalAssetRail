pragma solidity ^0.8.0;

import { AccessControl } from "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

contract FxOracle is AccessControl {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    // mapping of pair-hash → rate (18 decimals)
    mapping(bytes32 => uint256) public rates;

    event RateUpdated(bytes32 indexed pairHash, uint256 rate);

    constructor() {
        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setRate(string calldata from, string calldata to, uint256 rate) external onlyRole(GOVERNOR_ROLE) {
        bytes32 key = keccak256(abi.encodePacked(from, "/", to));
        rates[key] = rate;
        emit RateUpdated(key, rate);
    }

    function getRate(string calldata from, string calldata to) external view returns (uint256) {
        return rates[keccak256(abi.encodePacked(from, "/", to))];
    }
}
