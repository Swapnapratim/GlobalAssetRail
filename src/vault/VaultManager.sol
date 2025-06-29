// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC4626 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { RoleManager } from "../onboarding/RoleManager.sol";

/// @notice PoC VaultManager: batch deposits + minimal yield uplift
contract VaultManager is ERC4626, RoleManager {
    using SafeERC20 for IERC20;

    struct Asset {
        IERC20 token;
        uint256 navPerToken;  
        uint256 haircutBP;   
        bool    active;
        uint256 totalDeposited;
    }

    mapping(address=>Asset) public assets;    
    address[] public assetList;
    uint256 public totalValue;   

    constructor(
      IERC20 _dummy, 
      string memory _name, 
      string memory _symbol
    ) ERC4626(_dummy) ERC20(_name, _symbol)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN, msg.sender);
    }

    function addAsset(address a, uint256 haircutBP) external onlyRole(ADMIN) {
        assets[a] = Asset(IERC20(a), 1e18, haircutBP, true, 0);
        assetList.push(a);
    }

    function depositBatch(address[] calldata _assets, uint256[] calldata _amounts, address _for) external onlyRole(INSTITUTION) {
        require(_assets.length == _amounts.length, "VM: bad input");
        uint256 sum;

        for (uint i; i < _assets.length; i++) {
            Asset storage A = assets[_assets[i]];
            require(A.active, "VM: !asset");
            uint256 amt = _amounts[i];
            A.token.safeTransferFrom(msg.sender, address(this), amt);

            uint256 navVal = (amt * A.navPerToken) / 1e18;
            uint256 adj    = navVal * (10000 - A.haircutBP) / 10000;
            sum += adj;
            A.totalDeposited += amt;
        }

        uint256 shares = totalSupply() == 0
        ? sum
        : (sum * totalSupply()) / totalValue;  

        totalValue += sum;
        _mint(_for, shares);
    }


    function updateAssetNav(address a, uint256 nav) external onlyRole(SENTINEL) {
        Asset storage A = assets[a];
        require(A.active, "VM: !asset");
        A.navPerToken = nav;
    }

    function recordAccruedYield(uint256 yieldAmt) external onlyRole(SENTINEL) {
        totalValue += yieldAmt;
    }

    function totalAssets() public view override returns (uint256) {
        return totalValue;
    }

    function getAssetList() external view returns (address[] memory) {
        return assetList;
    }
    function grantSentinelRole(address oracle) external onlyRole(ADMIN) {
        _grantRole(SENTINEL, oracle);
    }
}
