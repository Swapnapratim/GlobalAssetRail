const source = `
const CUSTODY_API = "https:api.com"; 

const yieldRequest = Functions.makeHttpRequest({
  url: \`\${CUSTODY_API}/getTotalYield\`,
  method: "GET",
  headers: {
    "Content-Type": "application/json"
  }
});

const response = await yieldRequest;

if (response.error) {
  throw Error("Yield request failed");
}

const totalYield = response.data.totalYield;

// Return the total yield as bytes (already in 18 decimals from API)
return Functions.encodeUint256(totalYield);
`;

module.exports = { source };
