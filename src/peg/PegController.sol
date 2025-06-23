// // src/peg/PegController.sol

// pragma solidity ^0.8.0;

// import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
// import "../vault/VaultManager.sol";
// import "../oracle/NavOracle.sol";
// import "../oracle/FxOracle.sol";
// // import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// contract PegController is AccessControl {
//     bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

//     VaultManager public immutable vault;
//     NavOracle    public immutable navOracle;
//     FxOracle     public immutable fxOracle;
//     // IUniswapV2Router02 public immutable router;

//     uint256 public baseFeeBP;
//     uint256 public maxFeeBP;
//     uint256 public pegThresholdBP;

//     constructor(
//         address _vault,
//         address _navOracle,
//         address _fxOracle,
//         // address _router,
//         uint256 _baseFeeBP,
//         uint256 _maxFeeBP,
//         uint256 _pegThresholdBP
//     ) {
//         vault      = VaultManager(_vault);
//         navOracle  = NavOracle(_navOracle);
//         fxOracle   = FxOracle(_fxOracle);
//         // router     = IUniswapV2Router02(_router);
//         baseFeeBP      = _baseFeeBP;
//         maxFeeBP       = _maxFeeBP;
//         pegThresholdBP = _pegThresholdBP;
//         grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
//     }

//     /// @notice Returns current mint fee in BP for `amount` of stablecoin
//     function getMintFeeBP(uint256 amount) public view returns (uint256) {
//         uint256 utilization = vault.getCurrentCollateralRatio();
//         // higher utilization → higher fee
//         uint256 fee = baseFeeBP + (utilization > pegThresholdBP
//             ? (utilization - pegThresholdBP) * (maxFeeBP - baseFeeBP) / (10000 - pegThresholdBP)
//             : 0);
//         return fee;
//     }

//     /// @notice Returns current burn fee in BP
//     function getBurnFeeBP(uint256 amount) public view returns (uint256) {
//         // you could use on-chain price vs. fxOracle for peg deviation
//         return getMintFeeBP(amount);
//     }

//     /// @notice Hooks called by StableToken
//     function onMint(address to, uint256 amount) external onlyRole(GOVERNOR_ROLE) {
//         uint256 feeBP = getMintFeeBP(amount);
//         // collect fee into insurance vault, mint net to `to`
//     }

//     function onBurn(address from, uint256 amount) external onlyRole(GOVERNOR_ROLE) {
//         uint256 feeBP = getBurnFeeBP(amount);
//         // burn amount+fee, send fee to insurance vault
//     }
// }
