// fetchNav.js
import { Functions } from "@chainlink/functions-toolkit";
import { ethers }    from "ethers";

export const generateRequest = async (assetKey) => {
  const CUSTODY_API = "https://your.api.domain";

  let totalNav = ethers.BigNumber.from(0);

  if (assetKey.startsWith("BALANCE_")) {
    // portfolio NAV for an institution
    const addr = assetKey.split("_")[1];
    const resp = await Functions.fetch(`${CUSTODY_API}/balance/${addr}`);
    const balData = await resp.json(); // { "INR-SOV-01":"1000000", ... }

    // iterate each holding
    for (const [key, amtStr] of Object.entries(balData)) {
      const cfg = await getAssetConfig(key);
      const price = await fetchPrice(key);
      const amt   = ethers.BigNumber.from(amtStr);
      // apply haircut: net = amt * price * (1 - haircutBP/10000)
      const gross = amt.mul(price).div(ethers.BigNumber.from(10).pow(cfg.decimals));
      const net   = gross.mul(10000 - cfg.haircutBP).div(10000);
      totalNav = totalNav.add(net);
    }
  } else {
    // single‐asset NAV
    const price = await fetchPrice(assetKey);
    totalNav = ethers.BigNumber.from(price);
  }

  // return raw uint256 NAV
  const encoded = Functions.encodeAbiParameters(["uint256"], [totalNav.toString()]);
  return Functions.standardResponse(encoded);
};

// helper: map assetKey → asset config (decimals & haircutBP)
async function getAssetConfig(key) {
  const resp = await Functions.fetch("https://your.api.domain/assets");
  const catalog = await resp.json();
  return catalog[key];
}

// helper: fetch price from two mock APIs and take median
async function fetchPrice(key) {
  const apis = {
    "INR-SOV-01": [
      "https://apiA.example.com/price?symbol=INR1234",
      "https://apiB.example.com/v1/INR1234"
    ],
    "INR-CORP-ABC": [ /* … */ ],
    "GOLD-1OZ": [ /* … */ ],
    // …
  }[key];
  const results = await Promise.allSettled(apis.map(u => Functions.fetch(u)));
  const prices  = results
    .filter(r => r.status === "fulfilled")
    .map(r => JSON.parse(r.value).price);

  if (prices.length === 0) throw new Error("No price sources");
  prices.sort((a,b)=>a-b);
  const mid = Math.floor(prices.length/2);
  return prices.length%2 ? prices[mid] : (prices[mid-1]+prices[mid])/2;
}
