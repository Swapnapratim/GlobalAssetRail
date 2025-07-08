// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Test.sol";
// import "../src/vault/VaultManager.sol";
// import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// contract MockERC20 is ERC20 {
//     constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
//     function mint(address to, uint256 amount) external {
//         _mint(to, amount);
//     }
// }

// contract VaultManagerTest is Test {
//     VaultManager vault;
//     MockERC20 token1;
//     MockERC20 token2;
//     MockERC20 dummyToken;
    
//     address user1 = address(0x1);
//     address user2 = address(0x2);
//     address sentinel = address(0x3);

//     function setUp() public {
//         // dummyToken = new MockERC20("Dummy", "DUM");
//         vault = new VaultManager(IERC20(address(0)), "Test Vault", "TV");
        
//         token1 = new MockERC20("Token1", "T1");
//         token2 = new MockERC20("Token2", "T2");
        
//         vault.addAsset(address(token1), 500);
//         vault.addAsset(address(token2), 1000);
//         vault.grantSentinelRole(sentinel);
        
//         token1.mint(user1, 1000e18);
//         token2.mint(user1, 1000e18);
//         token1.mint(user2, 1000e18);
//         token2.mint(user2, 1000e18);
        
//         vm.prank(user1);
//         token1.approve(address(vault), type(uint256).max);
//         vm.prank(user1);
//         token2.approve(address(vault), type(uint256).max);
        
//         vm.prank(user2);
//         token1.approve(address(vault), type(uint256).max);
//         vm.prank(user2);
//         token2.approve(address(vault), type(uint256).max);
//     }

//     function testSingleAssetDeposit() public {
//         address[] memory assets = new address[](1);
//         uint256[] memory amounts = new uint256[](1);
        
//         assets[0] = address(token1);
//         amounts[0] = 100e18;
        
//         vm.prank(user1);
//         vault.depositBatch(assets, amounts);
        
//         assertEq(vault.balanceOf(user1), 95e18);
//         assertEq(vault.totalAssets(), 95e18);
//     }

//     function testMultiAssetDeposit() public {
//         address[] memory assets = new address[](2);
//         uint256[] memory amounts = new uint256[](2);
        
//         assets[0] = address(token1);
//         assets[1] = address(token2);
//         amounts[0] = 100e18;
//         amounts[1] = 50e18;
        
//         vm.prank(user1);
//         vault.depositBatch(assets, amounts);
        
//         uint256 expectedValue = 95e18 + 45e18;
//         assertEq(vault.balanceOf(user1), expectedValue);
//         assertEq(vault.totalAssets(), expectedValue);
//     }

//     function testMultipleUsersDeposit() public {
//         address[] memory assets = new address[](1);
//         uint256[] memory amounts = new uint256[](1);
        
//         assets[0] = address(token1);
//         amounts[0] = 100e18;
        
//         vm.prank(user1);
//         vault.depositBatch(assets, amounts);
        
//         vm.prank(user2);
//         vault.depositBatch(assets, amounts);
        
//         assertEq(vault.balanceOf(user1), 95e18);
//         assertEq(vault.balanceOf(user2), 95e18);
//         assertEq(vault.totalAssets(), 190e18);
//     }

//     function testNavUpdate() public {
//         address[] memory assets = new address[](1);
//         uint256[] memory amounts = new uint256[](1);
        
//         assets[0] = address(token1);
//         amounts[0] = 100e18;
        
//         vm.prank(user1);
//         vault.depositBatch(assets, amounts);
        
//         vm.prank(sentinel);
//         vault.updateAssetNav(address(token1), 2e18);
        
//         assertEq(vault.totalAssets(), 95e18);
//     }

//     function testYieldAccrual() public {
//         address[] memory assets = new address[](1);
//         uint256[] memory amounts = new uint256[](1);
        
//         assets[0] = address(token1);
//         amounts[0] = 100e18;
        
//         vm.prank(user1);
//         vault.depositBatch(assets, amounts);
        
//         uint256 initialValue = vault.totalAssets();
        
//         vm.prank(sentinel);
//         vault.recordAccruedYield(10e18);
        
//         assertEq(vault.totalAssets(), initialValue + 10e18);
//     }

//     function testShareValueIncrease() public {
//         address[] memory assets = new address[](1);
//         uint256[] memory amounts = new uint256[](1);
        
//         assets[0] = address(token1);
//         amounts[0] = 100e18;
        
//         vm.prank(user1);
//         vault.depositBatch(assets, amounts);
        
//         uint256 initialShares = vault.balanceOf(user1);
        
//         vm.prank(sentinel);
//         vault.recordAccruedYield(95e18);
        
//         vm.prank(user2);
//         vault.depositBatch(assets, amounts);
        
//         assertEq(vault.balanceOf(user1), initialShares);
//         assertLt(vault.balanceOf(user2), initialShares);
//     }

//     function testGetAssetList() public {
//         address[] memory assetList = vault.getAssetList();
//         assertEq(assetList.length, 2);
//         assertEq(assetList[0], address(token1));
//         assertEq(assetList[1], address(token2));
//     }

//     function testFailInvalidAsset() public {
//         address[] memory assets = new address[](1);
//         uint256[] memory amounts = new uint256[](1);
        
//         assets[0] = address(0x999);
//         amounts[0] = 100e18;
        
//         vm.prank(user1);
//         vault.depositBatch(assets, amounts);
//     }

//     function testFailMismatchedArrays() public {
//         address[] memory assets = new address[](2);
//         uint256[] memory amounts = new uint256[](1);
        
//         assets[0] = address(token1);
//         assets[1] = address(token2);
//         amounts[0] = 100e18;
        
//         vm.prank(user1);
//         vault.depositBatch(assets, amounts);
//     }
// }
