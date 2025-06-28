// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Pausable } from "../../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { RoleManager } from "../onboarding/RoleManager.sol";
import { VaultManager } from "../vault/VaultManager.sol";
import { FxOracle } from "../oracle/FxOracle.sol";

interface IStableToken {
    function mintForRecipient(address recipient, uint256 amount) external;
}

contract StableToken is ERC20, ERC20Permit, RoleManager, Pausable, ReentrancyGuard {
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_MINT_FEE = 500;
    uint256 public constant MAX_BURN_FEE = 500;
    uint256 public constant MIN_COLLATERAL_RATIO = 15000; // 150%

    address public vaultManager;
    address public protocolTreasury;
    address public fxOracle;
    string public currencyPair;
    
    uint8 private _decimals;
    
    uint256 public mintFee;
    uint256 public burnFee;
    uint256 public totalFeesCollected;
    
    uint256 public maxMintPerTx;
    uint256 public maxBurnPerTx;
    uint256 public dailyMintLimit;
    uint256 public dailyBurnLimit;
    
    mapping(uint256 => uint256) public dailyMintedAmount;
    mapping(uint256 => uint256) public dailyBurnedAmount;
    mapping(address => uint256) public lastMintTimestamp;
    mapping(address => uint256) public lastBurnTimestamp;
    mapping(address => uint256) public userMintedAmount;
    
    uint256 public mintCooldown = 0;
    uint256 public burnCooldown = 0;

    event Minted(address indexed to, uint256 amount, uint256 fee, uint256 collateralValue, address indexed minter);
    event Burned(address indexed from, uint256 amount, uint256 fee, address indexed burner);
    event PegStatusChecked(bool isPegged, uint256 currentRate, uint256 deviation);
    event FeesUpdated(uint256 newMintFee, uint256 newBurnFee);
    event FeesCollected(address indexed treasury, uint256 amount);
    event LimitsUpdated(uint256 maxMint, uint256 maxBurn, uint256 dailyMint, uint256 dailyBurn);
    event VaultManagerUpdated(address indexed oldVault, address indexed newVault);

    modifier onlyVaultManager() {
        require(msg.sender == vaultManager, "NOT_VAULT_MANAGER");
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

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _tokenDecimals,
        address _vaultManager
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        require(_tokenDecimals <= 18, "INVALID_DECIMALS");
        require(_vaultManager != address(0), "INVALID_VAULT");
        
        _decimals = _tokenDecimals;
        vaultManager = _vaultManager;
        
        maxMintPerTx = 1_000_000 * 10**_tokenDecimals;
        maxBurnPerTx = 1_000_000 * 10**_tokenDecimals;
        dailyMintLimit = 10_000_000 * 10**_tokenDecimals;
        dailyBurnLimit = 10_000_000 * 10**_tokenDecimals;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN, msg.sender);
    }

    function mint(address to, uint256 amount, uint256 collateralValue) external 
        nonReentrant 
        whenNotPaused 
        onlyVaultManager 
        withinLimits(amount, true)
        respectsCooldown(to, lastMintTimestamp[to], mintCooldown)
    {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external 
        nonReentrant 
        whenNotPaused 
        onlyVaultManager 
        withinLimits(amount, false)
        respectsCooldown(from, lastBurnTimestamp[from], burnCooldown)
    {
        _burn(from, amount);
    }

    function mintForMerchant(uint256 amount) public 
        nonReentrant 
        whenNotPaused 
        withinLimits(amount, true)
        respectsCooldown(msg.sender, lastMintTimestamp[msg.sender], mintCooldown)
    {
        require(_hasEnoughCollateral(msg.sender, amount), "INSUFFICIENT_COLLATERAL");
        
        userMintedAmount[msg.sender] += amount;
        lastMintTimestamp[msg.sender] = block.timestamp;
        dailyMintedAmount[_getCurrentDay()] += amount;
        
        _mint(msg.sender, amount);
        emit Minted(msg.sender, amount, 0, 0, msg.sender);
    }

    function burnFromMerchant(uint256 amount) external 
        nonReentrant 
        whenNotPaused 
        withinLimits(amount, false)
        respectsCooldown(msg.sender, lastBurnTimestamp[msg.sender], burnCooldown)
    {
        require(balanceOf(msg.sender) >= amount, "INSUFFICIENT_BALANCE");
        
        userMintedAmount[msg.sender] -= amount;
        lastBurnTimestamp[msg.sender] = block.timestamp;
        dailyBurnedAmount[_getCurrentDay()] += amount;
        
        _burn(msg.sender, amount);
        emit Burned(msg.sender, amount, 0, msg.sender);
    }

    function crossBorderTransfer(
        address destinationToken,
        uint256 amount,
        address recipient
    ) external {
        uint256 fxAdjustedAmount = _getFxAdjustedAmount(amount, destinationToken);
        
        burnFromMerchant(amount);
        IStableToken(destinationToken).mintForRecipient(recipient, fxAdjustedAmount);
    }

    function _getFxAdjustedAmount(uint256 amount, address destToken) internal view returns (uint256) {
        // sINR → sUSD: amount * (INR/USD rate)
        // Example: 83 sINR → 1 sUSD when 1 USD = 83 INR
        return (amount * getSourceRate()) / getDestRate(destToken);
    }



    function setFxOracle(address _fxOracle, string memory _currencyPair) external onlyRole(ADMIN) {
        fxOracle = _fxOracle;
        currencyPair = _currencyPair;
    }

    function checkPegStatus() public view returns (bool pegged, uint256 currentRate, uint256 deviation) {
        if (fxOracle == address(0)) return (true, 1e18, 0);
        
        string memory pair = currencyPair;
        string[] memory parts = _splitPair(pair);
        
        return FxOracle(fxOracle).checkPegStatus(parts[0], parts[1]);
    }

    function mintForMerchantWithPegCheck(uint256 amount) external {
        (bool pegged,,) = checkPegStatus();
        require(pegged, "STABLECOIN_DEPEGGED");
        
        mintForMerchant(amount);
    }

    function emergencyPauseIfDepegged() external {
        (bool pegged,, uint256 deviation) = checkPegStatus();
        
        if (!pegged && deviation > 1000) {
            _pause();
            emit PegStatusChecked(pegged, 0, deviation);
        }
    }

    function _hasEnoughCollateral(address user, uint256 mintAmount) internal view returns (bool) {
        uint256 userCollateralValue = _getUserCollateralValue(user);
        uint256 totalMinted = userMintedAmount[user] + mintAmount;
        uint256 requiredCollateral = (totalMinted * MIN_COLLATERAL_RATIO) / BASIS_POINTS;
        
        return userCollateralValue >= requiredCollateral;
    }

    function _getUserCollateralValue(address user) internal view returns (uint256) {
        if (vaultManager == address(0)) return 0;
        
        try VaultManager(vaultManager).balanceOf(user) returns (uint256 shares) {
            if (shares == 0) return 0;
            
            uint256 totalShares = VaultManager(vaultManager).totalSupply();
            uint256 totalAssets = VaultManager(vaultManager).totalAssets();
            
            return (shares * totalAssets) / totalShares;
        } catch {
            return 0;
        }
    }

    function _splitPair(string memory pair) internal pure returns (string[] memory) {
        string[] memory parts = new string[](2);
        
        if (keccak256(bytes(pair)) == keccak256("sINR/INR")) {
            parts[0] = "sINR";
            parts[1] = "INR";
        } else if (keccak256(bytes(pair)) == keccak256("sYEN/YEN")) {
            parts[0] = "sYEN";
            parts[1] = "YEN";
        } else if (keccak256(bytes(pair)) == keccak256("sUSD/USD")) {
            parts[0] = "sUSD";
            parts[1] = "USD";
        }
        
        return parts;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    function getCurrentMintFee() external view returns (uint256) {
        return mintFee;
    }
    
    function getCurrentBurnFee() external view returns (uint256) {
        return burnFee;
    }
    
    function getUserCollateralRatio(address user) external view returns (uint256) {
        uint256 minted = userMintedAmount[user];
        if (minted == 0) return type(uint256).max;
        
        uint256 collateralValue = _getUserCollateralValue(user);
        return (collateralValue * BASIS_POINTS) / minted;
    }

    function canMint(address user, uint256 amount) external view returns (bool) {
        return _hasEnoughCollateral(user, amount);
    }
    
    function _getCurrentDay() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }
    
    function _getDailyMinted() internal view returns (uint256) {
        return dailyMintedAmount[_getCurrentDay()];
    }
    
    function _getDailyBurned() internal view returns (uint256) {
        return dailyBurnedAmount[_getCurrentDay()];
    }

    // Admin functions (updateFees, updateLimits, etc.) - keeping existing ones
    function updateFees(uint256 _mintFee, uint256 _burnFee) external onlyRole(ADMIN) {
        require(_mintFee <= MAX_MINT_FEE, "MINT_FEE_TOO_HIGH");
        require(_burnFee <= MAX_BURN_FEE, "BURN_FEE_TOO_HIGH");
        
        mintFee = _mintFee;
        burnFee = _burnFee;
        
        emit FeesUpdated(_mintFee, _burnFee);
    }

    function setVaultManager(address _vaultManager) external onlyRole(ADMIN) {
        require(_vaultManager != address(0), "INVALID_VAULT");
        address oldVault = vaultManager;
        vaultManager = _vaultManager;
        emit VaultManagerUpdated(oldVault, _vaultManager);
    }

    function pause() external onlyRole(ADMIN) {
        _pause();
    }
    
    function unpause() external onlyRole(ADMIN) {
        _unpause();
    }
}
