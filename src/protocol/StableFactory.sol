// pragma solidity ^0.8.0;

// import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
// import "../vault/VaultManager.sol";
// import "../token/StableToken.sol";
// // import "../token/ShareToken.sol";
// import "../oracle/NavOracle.sol";
// import "../oracle/FxOracle.sol";
// import "../peg/PegController.sol";

// contract StableFactory is AccessControl {
//     bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

//     event StableBundleDeployed(
//         address indexed stableToken,
//         address shareToken,
//         address vaultManager,
//         address navOracle
//     );

//     constructor() {
//         grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
//         grantRole(DEPLOYER_ROLE, msg.sender);
//     }

//     function deployBundle(
//         string calldata name,
//         string calldata symbol,
//         address rwaToken,
//         address router,
//         uint256 baseFeeBP,
//         uint256 maxFeeBP,
//         uint256 pegThresholdBP,
//         uint256 targetCollRatio
//     )
//         external onlyRole(DEPLOYER_ROLE)
//         returns (address stableToken, address shareToken, address vaultManager, address navOracle)
//     {
//         // shareToken   = address(new ShareToken(/*…args*/));
//         navOracle    = address(new NavOracle());
//         vaultManager = address(new VaultManager(
//             IERC20(rwaToken),
//             name,
//             symbol,
//             targetCollRatio,
//             address(navOracle)
//         ));
//         FxOracle fx   = new FxOracle();
//         PegController peg = new PegController(
//             vaultManager, navOracle, address(fx), /*router,*/
//             baseFeeBP, maxFeeBP, pegThresholdBP
//         );
//         stableToken  = address(new StableToken(
//             name,
//             symbol,
//             18,
//             vaultManager
//         ));

//         // grant roles so StableToken ↔ VaultManager ↔ PegController interoperate:
//         VaultManager(vaultManager).grantRole(VaultManager(vaultManager).STABLE_TOKEN_ROLE(), stableToken);
//         StableToken(stableToken).grantRole(StableToken(stableToken).MINTER_ROLE(), address(peg));
//         StableToken(stableToken).grantRole(StableToken(stableToken).BURNER_ROLE(), address(peg));

//         emit StableBundleDeployed(stableToken, shareToken, vaultManager, navOracle);
//     }
// }
