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
        uint256 navPerToken;  // 18-decimals NAV
        uint256 haircutBP;    // basis points
        bool    active;
        uint256 totalDeposited;
    }

    mapping(address=>Asset) public assets;
    address[] public assetList;
    uint256 public totalValue;    // sum of NAV-adjusted, haircut-applied deposits

    constructor(
      IERC20 _dummy, 
      string memory _name, 
      string memory _symbol
    ) ERC4626(_dummy) ERC20(_name, _symbol)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN, msg.sender);
    }

    /// @notice Add a mock collateral asset for PoC
    function addAsset(address a, uint256 haircutBP) external onlyRole(ADMIN) {
        assets[a] = Asset(IERC20(a), 1e18, haircutBP, true, 0);
        assetList.push(a);
    }

    /// @notice Batch deposit of any number of assets; mints ERC4626 shares
    function depositBatch(address[] calldata as_, uint256[] calldata amts) external {
        require(as_.length == amts.length, "VM: bad input");
        uint256 sum;

        for (uint i; i < as_.length; i++) {
            Asset storage A = assets[as_[i]];
            require(A.active, "VM: !asset");
            uint256 amt = amts[i];
            A.token.safeTransferFrom(msg.sender, address(this), amt);

            uint256 navVal = (amt * A.navPerToken) / 1e18;
            uint256 adj    = navVal * (10000 - A.haircutBP) / 10000;
            sum += adj;
            A.totalDeposited += amt;
        }

        totalValue += sum;
        uint256 shares = totalSupply() == 0
          ? sum
          : (sum * totalSupply()) / totalValue;

        _mint(msg.sender, shares);
    }

    /// @notice Update per-token NAV (price moves)
    function updateAssetNav(address a, uint256 nav) external onlyRole(SENTINEL) {
        Asset storage A = assets[a];
        require(A.active, "VM: !asset");
        A.navPerToken = nav;
    }

    /// @notice Credit total yield (coupons/dividends) to all LPs
    function recordAccruedYield(uint256 yieldAmt) external onlyRole(SENTINEL) {
        totalValue += yieldAmt;
    }

    /// @dev ERC4626 totalAssets = vault NAV
    function totalAssets() public view override returns (uint256) {
        return totalValue;
    }
}
