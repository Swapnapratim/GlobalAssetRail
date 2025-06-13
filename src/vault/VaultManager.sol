// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC4626 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "../../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import { RoleManager } from "../onboarding/RoleManager.sol";

/**
 * @title VaultManager
 * @notice ERC4626-style vault managing collateral for country-specific stablecoins
 * @dev - Handles deposits of tokenized RWAs (bonds, equities, gold) as collateral
 *      - Maintains over-collateralization ratios per asset tier
 *      - Integrates with Chainlink Functions for NAV updates and yield accrual
 *      - Issues ShareTokens representing LP positions in the vault
 *      - Enforces collateralization requirements for stablecoin minting
 *      - Manages yield distribution and protocol fees
 */
contract VaultManager is ERC4626, RoleManager, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 public constant COLLATERAL_PRECISION = 1e18;
    uint256 public constant MIN_COLLATERAL_RATIO = 120e16; // 120% minimum
    uint256 public constant MAX_COLLATERAL_RATIO = 300e16; // 300% maximum
    uint256 public constant PROTOCOL_FEE_BASIS_POINTS = 1000; // 10%
    uint256 public constant BASIS_POINTS = 10000;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    enum AssetTier {
        TIER_1, // Sovereign bonds (5% haircut)
        TIER_2, // Investment grade corporate debt (15% haircut)
        TIER_3  // Equities, gold, other assets (25% haircut)
    }

    struct CollateralAsset {
        IERC20 token;
        AssetTier tier;
        uint256 haircut; // Basis points (e.g., 500 = 5%)
        uint256 maxAllocation; // Maximum % of total collateral
        bool isActive;
        uint256 totalDeposited;
        uint256 lastNavUpdate;
        uint256 navPerToken; // NAV per token in underlying currency
    }

    struct YieldAccrual {
        uint256 totalYieldAccrued;
        uint256 lastYieldUpdate;
        uint256 protocolFeeAccrued;
        uint256 lpYieldAccrued;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    // Collateral management
    mapping(address => CollateralAsset) public collateralAssets;
    address[] public supportedAssets;
    mapping(address => mapping(address => uint256)) public userCollateralBalance;
    
    // Vault parameters
    uint256 public targetCollateralRatio;
    uint256 public totalCollateralValue; // In underlying currency
    uint256 public totalStablecoinMinted;
    uint256 public bufferPoolSize;
    uint256 public insuranceVaultBalance;
    
    // Yield management
    YieldAccrual public yieldData;
    mapping(address => uint256) public lastUserYieldIndex;
    
    // Oracle integration
    address public navOracle;
    address public fxOracle;
    uint256 public lastNavUpdate;
    uint256 public navUpdateThreshold = 1 hours;
    
    // Protocol addresses
    address public stableToken;
    address public protocolTreasury;
    // string public countryCurrency; // "INR", "JPY", etc.

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralDeposited(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 navValue
    );
    
    event CollateralWithdrawn(
        address indexed user,
        address indexed asset,
        uint256 amount,
        uint256 navValue
    );
    
    event YieldAccrued(
        uint256 totalYield,
        uint256 protocolFee,
        uint256 lpYield,
        uint256 timestamp
    );
    
    event NavUpdated(
        address indexed asset,
        uint256 oldNav,
        uint256 newNav,
        uint256 timestamp
    );
    
    event StablecoinMinted(
        address indexed user,
        uint256 amount,
        uint256 collateralValue,
        uint256 ratio
    );
    
    event StablecoinBurned(
        address indexed user,
        uint256 amount,
        uint256 collateralReleased
    );

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOracle() {
        require(hasRole(SENTINEL, msg.sender) || msg.sender == navOracle, "NOT_ORACLE");
        _;
    }

    modifier onlyStableToken() {
        require(msg.sender == stableToken, "NOT_STABLE_TOKEN");
        _;
    }

    modifier validCollateralRatio() {
        _;
        require(_checkCollateralRatio(), "INSUFFICIENT_COLLATERAL");
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        // string memory _countryCurrency,
        uint256 _targetCollateralRatio,
        address _navOracle
        // address _protocolTreasury
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        require(_targetCollateralRatio >= MIN_COLLATERAL_RATIO, "RATIO_TOO_LOW");
        require(_targetCollateralRatio <= MAX_COLLATERAL_RATIO, "RATIO_TOO_HIGH");
        
        // countryCurrency = _countryCurrency;
        targetCollateralRatio = _targetCollateralRatio;
        navOracle = _navOracle;
        // protocolTreasury = _protocolTreasury;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        COLLATERAL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a new collateral asset with specified parameters
     * @param _asset Address of the tokenized RWA
     * @param _tier Asset tier (TIER_1, TIER_2, TIER_3)
     * @param _haircut Haircut in basis points
     * @param _maxAllocation Maximum allocation percentage
     */
    function addCollateralAsset(
        address _asset,
        AssetTier _tier,
        uint256 _haircut,
        uint256 _maxAllocation
    ) external onlyRole(ADMIN) {
        require(_asset != address(0), "INVALID_ASSET");
        require(_haircut <= 5000, "HAIRCUT_TOO_HIGH"); // Max 50%
        require(_maxAllocation <= 10000, "ALLOCATION_TOO_HIGH"); // Max 100%
        
        collateralAssets[_asset] = CollateralAsset({
            token: IERC20(_asset),
            tier: _tier,
            haircut: _haircut,
            maxAllocation: _maxAllocation,
            isActive: true,
            totalDeposited: 0,
            lastNavUpdate: block.timestamp,
            navPerToken: COLLATERAL_PRECISION
        });
        
        supportedAssets.push(_asset);
    }

    /**
     * @notice Deposit collateral assets to the vault
     * @param _asset Address of the collateral asset
     * @param _amount Amount to deposit
     * @return shares Number of shares minted
     */
    function depositCollateral(
        address _asset,
        uint256 _amount
    ) external nonReentrant whenNotPaused onlyRole(INSTITUTION) returns (uint256 shares) {
        require(collateralAssets[_asset].isActive, "ASSET_NOT_SUPPORTED");
        require(_amount > 0, "INVALID_AMOUNT");
        
        CollateralAsset storage asset = collateralAssets[_asset];
        
        // Transfer tokens to vault
        asset.token.safeTransferFrom(msg.sender, address(this), _amount);
        
        // Calculate NAV-adjusted value
        uint256 navValue = (_amount * asset.navPerToken) / COLLATERAL_PRECISION;
        uint256 adjustedValue = navValue - (navValue * asset.haircut / BASIS_POINTS);
        
        // Update storage
        asset.totalDeposited += _amount;
        userCollateralBalance[msg.sender][_asset] += _amount;
        totalCollateralValue += adjustedValue;
        
        // Mint shares based on current share price
        shares = _convertToShares(adjustedValue);
        _mint(msg.sender, shares);
        
        emit CollateralDeposited(msg.sender, _asset, _amount, navValue);
    }

    /**
     * @notice Withdraw collateral assets from the vault
     * @param _asset Address of the collateral asset
     * @param _amount Amount to withdraw
     * @param _shares Number of shares to burn
     */
    function withdrawCollateral(
        address _asset,
        uint256 _amount,
        uint256 _shares
    ) external nonReentrant onlyRole(INSTITUTION) validCollateralRatio {
        require(collateralAssets[_asset].isActive, "ASSET_NOT_SUPPORTED");
        require(_amount > 0 && _shares > 0, "INVALID_AMOUNT");
        require(userCollateralBalance[msg.sender][_asset] >= _amount, "INSUFFICIENT_BALANCE");
        require(balanceOf(msg.sender) >= _shares, "INSUFFICIENT_SHARES");
        
        CollateralAsset storage asset = collateralAssets[_asset];
        
        // Calculate NAV-adjusted value
        uint256 navValue = (_amount * asset.navPerToken) / COLLATERAL_PRECISION;
        uint256 adjustedValue = navValue - (navValue * asset.haircut / BASIS_POINTS);
        
        // Update storage
        asset.totalDeposited -= _amount;
        userCollateralBalance[msg.sender][_asset] -= _amount;
        totalCollateralValue -= adjustedValue;
        
        // Burn shares and transfer tokens
        _burn(msg.sender, _shares);
        asset.token.safeTransfer(msg.sender, _amount);
        
        emit CollateralWithdrawn(msg.sender, _asset, _amount, navValue);
    }

    /*//////////////////////////////////////////////////////////////
                        STABLECOIN MINTING/BURNING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint stablecoins against collateral
     * @param _to Address to mint tokens to
     * @param _amount Amount of stablecoins to mint
     */
    function mintStablecoin(
        address _to,
        uint256 _amount
    ) external onlyRole(STABLE_TOKEN_ROLE) validCollateralRatio {
        require(_amount > 0, "INVALID_AMOUNT");
        
        totalStablecoinMinted += _amount;
        
        uint256 collateralRatio = getCurrentCollateralRatio();
        
        emit StablecoinMinted(_to, _amount, totalCollateralValue, collateralRatio);
    }

    /**
     * @notice Burn stablecoins and release collateral
     * @param _from Address to burn tokens from
     * @param _amount Amount of stablecoins to burn
     */
    function burnStablecoin(
        address _from,
        uint256 _amount
    ) external onlyRole(STABLE_TOKEN_ROLE) {
        require(_amount > 0, "INVALID_AMOUNT");
        require(totalStablecoinMinted >= _amount, "INSUFFICIENT_MINTED");
        
        totalStablecoinMinted -= _amount;
        
        emit StablecoinBurned(_from, _amount, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        YIELD MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Record accrued yield from custodian via Chainlink Functions
     * @param _yieldAmount Total yield accrued since last update
     */
    function recordAccruedYield(uint256 _yieldAmount) external onlyOracle {
        require(_yieldAmount > 0, "INVALID_YIELD");
        
        uint256 protocolFee = (_yieldAmount * PROTOCOL_FEE_BASIS_POINTS) / BASIS_POINTS;
        uint256 lpYield = _yieldAmount - protocolFee;
        
        // Update yield data
        yieldData.totalYieldAccrued += _yieldAmount;
        yieldData.protocolFeeAccrued += protocolFee;
        yieldData.lpYieldAccrued += lpYield;
        yieldData.lastYieldUpdate = block.timestamp;
        
        // Increase total collateral value (NAV uplift)
        totalCollateralValue += lpYield;
        
        // Transfer protocol fee to treasury
        if (protocolFee > 0) {
            insuranceVaultBalance += protocolFee;
        }
        
        emit YieldAccrued(_yieldAmount, protocolFee, lpYield, block.timestamp);
    }

    /**
     * @notice Update NAV for a specific asset via Chainlink Functions
     * @param _asset Address of the asset
     * @param _newNavPerToken New NAV per token
     */
    function updateAssetNav(
        address _asset,
        uint256 _newNavPerToken
    ) external onlyOracle {
        require(collateralAssets[_asset].isActive, "ASSET_NOT_SUPPORTED");
        require(_newNavPerToken > 0, "INVALID_NAV");
        
        CollateralAsset storage asset = collateralAssets[_asset];
        uint256 oldNav = asset.navPerToken;
        
        // Update NAV and recalculate total collateral value
        uint256 oldValue = (asset.totalDeposited * oldNav) / COLLATERAL_PRECISION;
        uint256 newValue = (asset.totalDeposited * _newNavPerToken) / COLLATERAL_PRECISION;
        
        // Apply haircut
        uint256 oldAdjustedValue = oldValue - (oldValue * asset.haircut / BASIS_POINTS);
        uint256 newAdjustedValue = newValue - (newValue * asset.haircut / BASIS_POINTS);
        
        // Update storage
        asset.navPerToken = _newNavPerToken;
        asset.lastNavUpdate = block.timestamp;
        totalCollateralValue = totalCollateralValue - oldAdjustedValue + newAdjustedValue;
        lastNavUpdate = block.timestamp;
        
        emit NavUpdated(_asset, oldNav, _newNavPerToken, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get current collateralization ratio
     * @return ratio Current collateral ratio (18 decimals)
     */
    function getCurrentCollateralRatio() public view returns (uint256 ratio) {
        if (totalStablecoinMinted == 0) return type(uint256).max;
        return (totalCollateralValue * COLLATERAL_PRECISION) / totalStablecoinMinted;
    }

    /**
     * @notice Check if vault maintains minimum collateral ratio
     * @return bool True if adequately collateralized
     */
    function isAdequatelyCollateralized() external view returns (bool) {
        return getCurrentCollateralRatio() >= targetCollateralRatio;
    }

    /**
     * @notice Get total value of a specific asset
     * @param _asset Address of the asset
     * @return value Total NAV-adjusted value
     */
    function getAssetTotalValue(address _asset) external view returns (uint256 value) {
        CollateralAsset storage asset = collateralAssets[_asset];
        if (!asset.isActive) return 0;
        
        uint256 rawValue = (asset.totalDeposited * asset.navPerToken) / COLLATERAL_PRECISION;
        return rawValue - (rawValue * asset.haircut / BASIS_POINTS);
    }

    /**
     * @notice Get user's collateral value across all assets
     * @param _user Address of the user
     * @return value Total collateral value
     */
    function getUserCollateralValue(address _user) external view returns (uint256 value) {
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address asset = supportedAssets[i];
            CollateralAsset storage assetData = collateralAssets[asset];
            uint256 userBalance = userCollateralBalance[_user][asset];
            
            if (userBalance > 0) {
                uint256 rawValue = (userBalance * assetData.navPerToken) / COLLATERAL_PRECISION;
                uint256 adjustedValue = rawValue - (rawValue * assetData.haircut / BASIS_POINTS);
                value += adjustedValue;
            }
        }
    }

    /**
     * @notice Calculate maximum stablecoins that can be minted
     * @return maxMintable Maximum mintable amount
     */
    function getMaxMintableAmount() external view returns (uint256 maxMintable) {
        if (totalCollateralValue == 0) return 0;
        
        uint256 maxSupported = (totalCollateralValue * COLLATERAL_PRECISION) / targetCollateralRatio;
        return maxSupported > totalStablecoinMinted ? maxSupported - totalStablecoinMinted : 0;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256) {
        return totalCollateralValue;
    }

    function _convertToShares(uint256 assets) internal view returns (uint256) {
        return totalSupply() == 0 ? assets : assets.mulDiv(totalSupply(), totalAssets());
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        return totalSupply() == 0 ? shares : shares.mulDiv(totalAssets(), totalSupply());
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _checkCollateralRatio() internal view returns (bool) {
        return getCurrentCollateralRatio() >= targetCollateralRatio;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setStableToken(address _stableToken) external onlyRole(ADMIN) {
        stableToken = _stableToken;
    }

    function setTargetCollateralRatio(uint256 _ratio) external onlyRole(ADMIN) {
        require(_ratio >= MIN_COLLATERAL_RATIO && _ratio <= MAX_COLLATERAL_RATIO, "INVALID_RATIO");
        targetCollateralRatio = _ratio;
    }

    function setNavOracle(address _navOracle) external onlyRole(ADMIN) {
        navOracle = _navOracle;
    }

    function pause() external onlyRole(ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN) {
        _unpause();
    }

    function emergencyWithdraw(address _asset, uint256 _amount) external onlyRole(ADMIN) {
        IERC20(_asset).safeTransfer(protocolTreasury, _amount);
    }
}