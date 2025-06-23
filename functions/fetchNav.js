import { Functions } from "@chainlink/functions-toolkit";

export const generateRequest = async (args) => {
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
