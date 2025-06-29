const source = `
// Chainlink Function to handle custody transfer and deposit confirmation
// This function will be called by the DepositOracle contract

// Decode the arguments passed from the smart contract
const userAddress = args[0]; // Institution's address
const assetsEncoded = args[1]; // Comma-separated asset addresses
const amountsEncoded = args[2]; // Comma-separated amounts

// Decode the arrays from comma-separated strings
const assets = assetsEncoded.split(',').filter(addr => addr.length > 0);
const amounts = amountsEncoded.split(',').filter(amt => amt.length > 0).map(amt => parseInt(amt));

// API endpoints for custody operations
const CUSTODY_API_BASE = "https://gar-apis-akhgun4t8-sarvagnakadiyas-projects.vercel.app/";
const PROTOCOL_CUSTODY_ID = "protocol_vault_001"; // Protocol's custody account

// Step 1: Verify institution's demat holdings
const holdingsRequest = Functions.makeHttpRequest({
  url: \`\${CUSTODY_API_BASE}/verify-holdings\`,
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Authorization": "Bearer " + secrets.CUSTODY_API_KEY
  },
  data: {
    institutionAddress: userAddress,
    assets: assets,
    amounts: amounts
  }
});

const holdingsResponse = await holdingsRequest;
if (holdingsResponse.error || !holdingsResponse.data.verified) {
  throw Error("Holdings verification failed: " + (holdingsResponse.data?.message || "Unknown error"));
}

// Step 2: Transfer assets from institution custody to protocol custody
const transferRequest = Functions.makeHttpRequest({
  url: \`\${CUSTODY_API_BASE}/transfer-assets\`,
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Authorization": "Bearer " + secrets.CUSTODY_API_KEY
  },
  data: {
    fromInstitution: userAddress,
    toProtocol: PROTOCOL_CUSTODY_ID,
    assets: assets,
    amounts: amounts,
    transferId: Functions.requestId // Use Chainlink's request ID for tracking
  }
});

const transferResponse = await transferRequest;
if (transferResponse.error || !transferResponse.data.success) {
  throw Error("Asset transfer failed: " + (transferResponse.data?.message || "Unknown error"));
}

// Step 3: Generate ERC20 tokens for the transferred assets
// This would typically be done by the custody provider or a tokenization service
const tokenizationRequest = Functions.makeHttpRequest({
  url: \`\${CUSTODY_API_BASE}/mint-erc20\`,
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Authorization": "Bearer " + secrets.CUSTODY_API_KEY
  },
  data: {
    protocolAddress: PROTOCOL_CUSTODY_ID,
    assets: assets,
    amounts: amounts,
    recipient: userAddress // Institution receives the ERC20 tokens
  }
});

const tokenizationResponse = await tokenizationRequest;
if (tokenizationResponse.error || !tokenizationResponse.data.success) {
  throw Error("Tokenization failed: " + (tokenizationResponse.data?.message || "Unknown error"));
}

// Step 4: Return the confirmation data for on-chain deposit
// Return the data in a format that can be directly decoded by the smart contract
// Format: (address[] assets, uint256[] amounts, address user)
return Functions.encodeBytes(abi.encode(assets, amounts, userAddress));
`;

// For local testing and development
const generateRequest = async (args) => {
  const { Functions } = require("@chainlink/functions-toolkit");
  const { ethers } = require("ethers");

  const userAddress = args[0];
  const assetsEncoded = args[1];
  const amountsEncoded = args[2];

  // Mock implementation for testing
  console.log("Processing custody transfer for:", userAddress);
  console.log("Assets encoded:", assetsEncoded);
  console.log("Amounts encoded:", amountsEncoded);

  // Decode the comma-separated strings
  const assets = assetsEncoded.split(",").filter((addr) => addr.length > 0);
  const amounts = amountsEncoded
    .split(",")
    .filter((amt) => amt.length > 0)
    .map((amt) => parseInt(amt));

  console.log("Decoded assets:", assets);
  console.log("Decoded amounts:", amounts);

  // Simulate successful custody transfer
  const mockAssets = [
    "0x1234567890123456789012345678901234567890",
    "0x0987654321098765432109876543210987654321",
  ];
  const mockAmounts = ["1000000000000000000", "2000000000000000000"]; // 1 and 2 tokens

  // Encode the response in the same format as the Chainlink Function
  const abiCoder = new ethers.AbiCoder();
  const encodedResponse = abiCoder.encode(
    ["address[]", "uint256[]", "address"],
    [mockAssets, mockAmounts, userAddress]
  );

  return Functions.encodeBytes(encodedResponse);
};

module.exports = { source, generateRequest };
