// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Pausable } from "../../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { RoleManager } from "../onboarding/RoleManager.sol";
import { VaultManager } from "../vault/VaultManager.sol";

/**
 * @title StableToken
 * @notice Country-specific stablecoin (sINR, sYEN, etc.) pegged 1:1 to national fiat
 * @dev - Minting/burning controlled by VaultManager based on collateral ratios
 *      - Integrates with PegController for dynamic fee calculations
 *      - Supports ERC20Permit for gasless approvals
 *      - Emergency pause functionality for protocol security
 *      - Role-based access control for institutional participants
 */
contract StableToken is ERC20, ERC20Permit, RoleManager, Pausable, ReentrancyGuard {
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_MINT_FEE = 500; // 5% maximum mint fee
    uint256 public constant MAX_BURN_FEE = 500; // 5% maximum burn fee

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    // Core protocol addresses
    address public vaultManager;
    address public pegController;
    address public protocolTreasury;
    
    // Token metadata
    uint8 private _decimals;
    
    // Fee management
    uint256 public mintFee; // Basis points
    uint256 public burnFee; // Basis points
    uint256 public totalFeesCollected;
    
    // Minting limits
    uint256 public maxMintPerTx;
    uint256 public maxBurnPerTx;
    uint256 public dailyMintLimit;
    uint256 public dailyBurnLimit;
    
    // Daily tracking
    mapping(uint256 => uint256) public dailyMintedAmount; // day => amount
    mapping(uint256 => uint256) public dailyBurnedAmount; // day => amount
    
    // User tracking
    mapping(address => uint256) public lastMintTimestamp;
    mapping(address => uint256) public lastBurnTimestamp;
    uint256 public mintCooldown = 0; // No cooldown by default
    uint256 public burnCooldown = 0; // No cooldown by default

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event Minted(
        address indexed to,
        uint256 amount,
        uint256 fee,
        uint256 collateralValue,
        address indexed minter
    );
    
    event Burned(
        address indexed from,
        uint256 amount,
        uint256 fee,
        address indexed burner
    );
    
    event FeesUpdated(uint256 newMintFee, uint256 newBurnFee);
    event FeesCollected(address indexed treasury, uint256 amount);
    event LimitsUpdated(uint256 maxMint, uint256 maxBurn, uint256 dailyMint, uint256 dailyBurn);
    event VaultManagerUpdated(address indexed oldVault, address indexed newVault);
    event PegControllerUpdated(address indexed oldController, address indexed newController);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyVaultManager() {
        require(msg.sender == vaultManager, "NOT_VAULT_MANAGER");
        _;
    }
    
    modifier onlyPegController() {
        require(msg.sender == pegController, "NOT_PEG_CONTROLLER");
        _;
    }
    
    modifier respectsCooldown(address user, uint256 lastAction, uint256 cooldown) {
        require(block.timestamp >= lastAction + cooldown, "COOLDOWN_ACTIVE");
        _;
    }
    
    modifier withinLimits(uint256 amount, bool isMint) {
        if (isMint) {
            require(amount <= maxMintPerTx, "EXCEEDS_MAX_MINT");
            require(_getDailyMinted() + amount <= dailyMintLimit, "EXCEEDS_DAILY_MINT_LIMIT");
        } else {
            require(amount <= maxBurnPerTx, "EXCEEDS_MAX_BURN");
            require(_getDailyBurned() + amount <= dailyBurnLimit, "EXCEEDS_DAILY_BURN_LIMIT");
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _tokenDecimals,
        address _vaultManager
        // address _protocolTreasury
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        require(_tokenDecimals <= 18, "INVALID_DECIMALS");
        require(_vaultManager != address(0), "INVALID_VAULT");
        // require(_protocolTreasury != address(0), "INVALID_TREASURY");
        
        _decimals = _tokenDecimals;
        vaultManager = _vaultManager;
        // protocolTreasury = _protocolTreasury;
        
        // Initialize with reasonable defaults
        maxMintPerTx = 1_000_000 * 10**_tokenDecimals; // 1M tokens
        maxBurnPerTx = 1_000_000 * 10**_tokenDecimals; // 1M tokens
        dailyMintLimit = 10_000_000 * 10**_tokenDecimals; // 10M tokens daily
        dailyBurnLimit = 10_000_000 * 10**_tokenDecimals; // 10M tokens daily
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        MINTING & BURNING LOGIC
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Mint stablecoins against collateral in vault
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     * @param collateralValue USD value of collateral backing this mint
     */
    function mint(
        address to,
        uint256 amount,
        uint256 collateralValue
    ) external 
        nonReentrant 
        whenNotPaused 
        onlyVaultManager 
        withinLimits(amount, true)
        respectsCooldown(to, lastMintTimestamp[to], mintCooldown)
    {
        // VaultManager(vaultManager).mintStablecoin(to, amount);
        _mint(to, amount);
    }
    
    /**
     * @notice Burn stablecoins and release collateral
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(
        address from,
        uint256 amount
    ) external 
        nonReentrant 
        whenNotPaused 
        onlyVaultManager 
        withinLimits(amount, false)
        respectsCooldown(from, lastBurnTimestamp[from], burnCooldown)
    {
        // VaultManager(vaultManager).burnStablecoin(from, amount);
        _burn(from, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update mint and burn fees
     * @param _mintFee New mint fee in basis points
     * @param _burnFee New burn fee in basis points
     */
    function updateFees(uint256 _mintFee, uint256 _burnFee) external onlyRole(ADMIN) {
        require(_mintFee <= MAX_MINT_FEE, "MINT_FEE_TOO_HIGH");
        require(_burnFee <= MAX_BURN_FEE, "BURN_FEE_TOO_HIGH");
        
        mintFee = _mintFee;
        burnFee = _burnFee;
        
        emit FeesUpdated(_mintFee, _burnFee);
    }
    
    /**
     * @notice Update transaction and daily limits
     */
    function updateLimits(
        uint256 _maxMintPerTx,
        uint256 _maxBurnPerTx,
        uint256 _dailyMintLimit,
        uint256 _dailyBurnLimit
    ) external onlyRole(ADMIN) {
        maxMintPerTx = _maxMintPerTx;
        maxBurnPerTx = _maxBurnPerTx;
        dailyMintLimit = _dailyMintLimit;
        dailyBurnLimit = _dailyBurnLimit;
        
        emit LimitsUpdated(_maxMintPerTx, _maxBurnPerTx, _dailyMintLimit, _dailyBurnLimit);
    }
    
    /**
     * @notice Update cooldown periods
     */
    function updateCooldowns(uint256 _mintCooldown, uint256 _burnCooldown) external onlyRole(ADMIN) {
        mintCooldown = _mintCooldown;
        burnCooldown = _burnCooldown;
    }
    
    /**
     * @notice Update vault manager address
     */
    function setVaultManager(address _vaultManager) external onlyRole(ADMIN) {
        require(_vaultManager != address(0), "INVALID_VAULT");
        address oldVault = vaultManager;
        vaultManager = _vaultManager;
        emit VaultManagerUpdated(oldVault, _vaultManager);
    }
    
    /**
     * @notice Update peg controller address
     */
    function setPegController(address _pegController) external onlyRole(ADMIN) {
        address oldController = pegController;
        pegController = _pegController;
        emit PegControllerUpdated(oldController, _pegController);
    }
    
    /**
     * @notice Collect accumulated fees
     */
    function collectFees() external onlyRole(ADMIN) {
        uint256 amount = totalFeesCollected;
        totalFeesCollected = 0;
        emit FeesCollected(protocolTreasury, amount);
    }
    
    /**
     * @notice Emergency pause functionality
     */
    function pause() external onlyRole(ADMIN) {
        _pause();
    }
    
    function unpause() external onlyRole(ADMIN) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    function getCurrentMintFee() external view returns (uint256) {
        if (pegController != address(0)) {
            try IPegController(pegController).getMintFee(0, 0) returns (uint256 dynamicFee) {
                return dynamicFee;
            } catch {
                return mintFee;
            }
        }
        return mintFee;
    }
    
    function getCurrentBurnFee() external view returns (uint256) {
        if (pegController != address(0)) {
            try IPegController(pegController).getBurnFee(0) returns (uint256 dynamicFee) {
                return dynamicFee;
            } catch {
                return burnFee;
            }
        }
        return burnFee;
    }
    
    function getDailyMinted() external view returns (uint256) {
        return _getDailyMinted();
    }
    
    function getDailyBurned() external view returns (uint256) {
        return _getDailyBurned();
    }
    
    function getRemainingDailyMintLimit() external view returns (uint256) {
        uint256 minted = _getDailyMinted();
        return minted >= dailyMintLimit ? 0 : dailyMintLimit - minted;
    }
    
    function getRemainingDailyBurnLimit() external view returns (uint256) {
        uint256 burned = _getDailyBurned();
        return burned >= dailyBurnLimit ? 0 : dailyBurnLimit - burned;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _getCurrentDay() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }
    
    function _getDailyMinted() internal view returns (uint256) {
        return dailyMintedAmount[_getCurrentDay()];
    }
    
    function _getDailyBurned() internal view returns (uint256) {
        return dailyBurnedAmount[_getCurrentDay()];
    }
}

/**
 * @title IPegController
 * @notice Interface for PegController contract
 */
interface IPegController {
    function getMintFee(uint256 amount, uint256 collateralValue) external view returns (uint256);
    function getBurnFee(uint256 amount) external view returns (uint256);
}