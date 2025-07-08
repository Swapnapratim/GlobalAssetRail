// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Test.sol";
// import "../src/vault/VaultManager.sol";
// import "../src/token/StableToken.sol";
// import "../src/oracle/FxOracle.sol";
// import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// contract MockERC20 is ERC20 {
//     constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
//     function mint(address to, uint256 amount) external {
//         _mint(to, amount);
//     }
// }

// contract VaultStableTokenIntegrationTest is Test {
//     VaultManager vault;
//     StableToken stableToken;
//     FxOracle fxOracle;
//     MockERC20 asset1;
//     MockERC20 asset2;
//     MockERC20 dummyToken;
    
//     address merchant1 = address(0x1);
//     address merchant2 = address(0x2);
//     address institution = address(0x3);

//     function setUp() public {
//         dummyToken = new MockERC20("Dummy", "DUM");
//         vault = new VaultManager(IERC20(address(dummyToken)), "India Vault", "IV");
//         stableToken = new StableToken("Stable INR", "sINR", 18, address(vault));
//         fxOracle = new FxOracle();
        
//         asset1 = new MockERC20("INR Bond", "INRB");
//         asset2 = new MockERC20("INR Stock", "INRS");
        
//         vault.addAsset(address(asset1), 500);
//         vault.addAsset(address(asset2), 1000);
        
//         stableToken.setFxOracle(address(fxOracle), "sINR/INR");
        
//         asset1.mint(merchant1, 10000e18);
//         asset2.mint(merchant1, 10000e18);
//         asset1.mint(merchant2, 10000e18);
//         asset2.mint(merchant2, 10000e18);
//         asset1.mint(institution, 10000e18);
        
//         vm.prank(merchant1);
//         asset1.approve(address(vault), type(uint256).max);
//         vm.prank(merchant1);
//         asset2.approve(address(vault), type(uint256).max);
        
//         vm.prank(merchant2);
//         asset1.approve(address(vault), type(uint256).max);
//         vm.prank(merchant2);
//         asset2.approve(address(vault), type(uint256).max);
        
//         vm.prank(institution);
//         asset1.approve(address(vault), type(uint256).max);
//     }

//     function testMerchantCanMintWithSufficientCollateral() public {
//         address[] memory assets = new address[](1);
//         uint256[] memory amounts = new uint256[](1);
        
//         assets[0] = address(asset1);
//         amounts[0] = 1500e18;
        
//         vm.prank(merchant1);
//         vault.depositBatch(assets, amounts);
        
//         uint256 collateralValue = vault.balanceOf(merchant1);
//         uint256 maxMintable = (collateralValue * 10000) / 15000;
        
//         vm.prank(merchant1);
//         stableToken.mintForMerchant(maxMintable);
        
//         assertEq(stableToken.balanceOf(merchant1), maxMintable);
//         assertEq(stableToken.userMintedAmount(merchant1), maxMintable);
        
//         uint256 collateralRatio = stableToken.getUserCollateralRatio(merchant1);
//         assertGe(collateralRatio, 15000);
//     }

//     function testMerchantCannotMintWithInsufficientCollateral() public {
//         address[] memory assets = new address[](1);
//         uint256[] memory amounts = new uint256[](1);
        
//         assets[0] = address(asset1);
//         amounts[0] = 1000e18;
        
//         vm.prank(merchant1);
//         vault.depositBatch(assets, amounts);
        
//         uint256 collateralValue = vault.balanceOf(merchant1);
//         uint256 excessiveMint = (collateralValue * 10000) / 14000;
        
//         vm.prank(merchant1);
//         vm.expectRevert("INSUFFICIENT_COLLATERAL");
//         stableToken.mintForMerchant(excessiveMint);
        
//         assertEq(stableToken.balanceOf(merchant1), 0);
//         assertEq(stableToken.userMintedAmount(merchant1), 0);
//     }

//     function testMultipleMerchantsAndBurnFunctionality() public {
//         address[] memory assets = new address[](2);
//         uint256[] memory amounts = new uint256[](2);
        
//         assets[0] = address(asset1);
//         assets[1] = address(asset2);
//         amounts[0] = 1000e18;
//         amounts[1] = 500e18;
        
//         vm.prank(merchant1);
//         vault.depositBatch(assets, amounts);
        
//         amounts[0] = 2000e18;
//         amounts[1] = 0;
        
//         vm.prank(merchant2);
//         vault.depositBatch(assets, amounts);
        
       
//         vm.prank(merchant1);
//         stableToken.mintForMerchant(merchant1Mint);
        
//         vm.prank(merchant2);
//         stableToken.mintForMerchant(merchant2Mint);
        
//         assertEq(stableToken.balanceOf(merchant1), merchant1Mint);
//         assertEq(stableToken.balanceOf(merchant2), merchant2Mint);
        
//         uint256 burnAmount = merchant1Mint / 2;
        
//         vm.prank(merchant1);
//         stableToken.burnFromMerchant(burnAmount);
        
//         assertEq(stableToken.balanceOf(merchant1), merchant1Mint - burnAmount);
//         assertEq(stableToken.userMintedAmount(merchant1), merchant1Mint - burnAmount);
        
//         uint256 newCollateralRatio = stableToken.getUserCollateralRatio(merchant1);
//         assertGt(newCollateralRatio, 15000);
        
//         assertTrue(stableToken.canMint(merchant1, burnAmount));
//     }
// }
