const source = `
const assetAddress = args[0] || "0xbDcfBEd3188040926bbEaBD70a25cFbE081F428d";
const CUSTODY_API = "https://api.com"; 

const custodyRequest = Functions.makeHttpRequest({
  url: \`\${CUSTODY_API}/getAssetPrice\`,
  method: "POST",
  headers: {
    "Content-Type": "application/json"
  },
  data: { assetAddress }
});

const response = await custodyRequest;

if (response.error) {
  throw Error("Request failed");
}

const price = response.data.price;

// Return the price as bytes
return Functions.encodeUint256(price);
`;

// local testing
export const generateRequest = async (args) => {
  const { Functions } = require("@chainlink/functions-toolkit");
  
  const assetAddress = args[0] || "0xbDcfBEd3188040926bbEaBD70a25cFbE081F428d";
  const CUSTODY_API = "http://localhost:3000";
  
  const resp = await Functions.makeHttpRequest({
    url: `${CUSTODY_API}/getAssetPrice`,
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    data: { assetAddress }
  });
  
  if (resp.error) {
    throw Error("Request failed");
  }
  
  const price = resp.data.price;
  
  return Functions.encodeUint256(price);
};

module.exports = { source };
