// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { RoleManager } from "./RoleManager.sol";
import { ECDSA } from "../../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "../../lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
/**
 * @title KYCRegistry
 * @notice Manages registration and verification of off‑chain KYC attestations for institutional participants and merchant gateways.
 * @dev   - Stores a mapping of address => attestation signature, provided by a trusted off‑chain KYC provider.
 *        - Verifies each signature against an attestor public key and expiration timestamp embedded in the signed payload.
 *        - Emits events on registration and revocation for transparency and auditability.
 *        - Only accounts with the ADMIN_ROLE can register or revoke attestations.
 *        - Designed for minimal on‑chain storage and gas cost: signatures stored as bytes, lookup via mapping.
 *
 * Interfaces:
 *    function registerInstitution(address inst, bytes calldata kycSig) external onlyAdmin;
 *    function registerGateway(address gateway, bytes calldata sig) external onlyAdmin;
 *    function revokeAttestation(address acct) external onlyAdmin;
 *    function isVerified(address acct) external view returns (bool);
 */
contract KYCRegistry is RoleManager {
    // todo how to store attestations now MORE SECURELY
    // i am thinking of a storage where i just call attestation with a unique id and get all the details

    struct InstitutionOnboardingData {
        address participant;
        address delegetee;
        string name;
        bytes signature;
        uint256 timestampOfRegistration;
    }

    struct InstitiutionStorage {
        address delegetee;  
        uint256 registrationTimestamp;
        string name;
        bool isApproved;
    }

    struct Attestation {
        bytes signature;
        bool isVerified;
    }

    enum Phase {
        REQUESTED,
        VERIFIED,
        CANCELLED
    }

    mapping(address participant => InstitiutionStorage institutionStorage) public s_institutionData;
    mapping(string name => Attestation attestation) public s_attestation;  
    mapping(bytes32 selector => mapping(address participant => Phase phase)) public s_requestData;  

    modifier onlySentinel() {
        require(hasRole(SENTINEL, msg.sender), 'NOT SENTINEL');
        _;
    }
    constructor() {
        _grantRole(ADMIN, msg.sender);
        _grantRole(SENTINEL, msg.sender);
    }

    function requestRegisterInstitution(InstitutionOnboardingData memory data) external returns(address participant){
        // it will be request based so I need a request id
        // how do i generate a request id
        // if msg.sender is pariticipant , then no delegetee, just verify whether signature matches with pariticipant
        // if msg.sender 
        // request should be cancelled
        // now what do they have to sign? 
        if(msg.sender != data.participant || msg.sender != data.delegetee) 
            revert("CALLER IS NOT PARTICIPANT OR DELEGETEE");
        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    this.requestRegisterInstitution.selector,
                    data.participant,
                    data.delegetee,
                    data.name,
                    address(this),
                    data.timestampOfRegistration
                )
            )
        );
        address signer = ECDSA.recover(messageHash, data.signature);
        if(signer != data.participant)
            revert("SIGNER IS NOT PARTICIPANT");
        // requestId = uint256(messageHash);
        // form a request id and store it for admin or related to check and verify
        s_requestData[this.requestRegisterInstitution.selector][data.participant] = Phase.REQUESTED;
        // generate a request id and keep it into storage until it is executed and delete it after that 
        return data.participant;
    }   
    function executeRegisterInstitution(
        address participant, 
        bool isVerified, 
        InstitutionOnboardingData memory data
    ) external onlySentinel {
        // check if it is cancelled or already executed;
        if(s_requestData[this.requestRegisterInstitution.selector][participant] == Phase.CANCELLED) 
            revert('REQUEST ALREADY CANCELLED');
        if(s_requestData[this.requestRegisterInstitution.selector][participant] == Phase.VERIFIED) 
            revert('REQUEST ALREADY VERIFIED');
        if(isVerified)
            s_requestData[this.requestRegisterInstitution.selector][participant] = Phase.VERIFIED;
        
        InstitiutionStorage memory institutionStorage;

        institutionStorage.delegetee = data.delegetee;
        institutionStorage.registrationTimestamp = block.timestamp;
        institutionStorage.name = data.name;
        institutionStorage.isApproved = true;
        s_institutionData[data.participant] = institutionStorage;

        // attestation
        Attestation memory attestation;
        attestation.signature = data.signature;
        attestation.isVerified = true;
        s_attestation[data.name] = attestation;
        _grantRole(INSTITUTION, data.participant);
    }
}