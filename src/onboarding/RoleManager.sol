// SPDX-License-Identifier: MIT

import { AccessControl } from "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

pragma solidity ^0.8.0;
/**
 * @title RoleManager
 * @notice 
 * @dev   
*/ 
contract RoleManager is AccessControl {

    bytes32 public constant INSTITUTION = keccak256("INSTITUTION");

    bytes32 public constant SENTINEL = keccak256("SENTINEL");

    bytes32 public constant ADMIN = keccak256("ADMIN");

    bytes32 public constant PROTOCOL_CONTROLLER = keccak256("PROTOCOL_CONTROLLER");

    bytes32 public constant STABLE_TOKEN_ROLE = keccak256("STABLE_TOKEN_ROLE");

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

}