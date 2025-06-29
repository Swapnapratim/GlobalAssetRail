require("dotenv").config();
const express = require("express");
const bodyParser = require("body-parser");
const cors = require("cors");
const { ethers } = require("ethers");

////////////////////////////////////////////////////////////////////////////////
// MOCK INSTITUTION & ASSET CATALOG
////////////////////////////////////////////////////////////////////////////////

const ASSET_CATALOG = {
  "INR-SGB": {
    name: "Indian Sovereign Gold Bond",
    tier: 1,
    haircutBP: 500,
    country: "IN",
    decimals: 18,
    tokenAddr: "0xbDcfBEd3188040926bbEaBD70a25cFbE081F428d",
    yieldRate: 250,
    lastYieldDate: Date.now(),
  },
  "INR-CORP": {
    name: "Indian Corporate Bond",
    tier: 2,
    haircutBP: 1000,
    country: "IN",
    decimals: 18,
    tokenAddr: "0x4F1F27A247a11b41D85c1D9B22304D8DAB8ae736",
    yieldRate: 800,
    lastYieldDate: Date.now(),
  },
  "INR-MFD": {
    name: "Indian Mutual Fund",
    tier: 3,
    haircutBP: 200,
    country: "IN",
    decimals: 8,
    tokenAddr: "0x40fA3ffdefa6613680F98F75771b897F8020cdF7",
    yieldRate: 1200,
    lastYieldDate: Date.now(),
  },
};

const Prices = {
  "INR-SGB": 100,
  "INR-CORP": 1000,
  "INR-MFD": 10,
};

const PriceHistory = {
  "INR-SGB": [{ price: 100, timestamp: Date.now() }],
  "INR-CORP": [{ price: 1000, timestamp: Date.now() }],
  "INR-MFD": [{ price: 10, timestamp: Date.now() }],
};

const AccumulatedYields = {
  "INR-SGB": 0,
  "INR-CORP": 0,
  "INR-MFD": 0,
};

// Mock institution holdings (in real implementation, this would come from demat accounts)
const INSTITUTION_HOLDINGS = {
  "0x1234567890123456789012345678901234567890": {
    // Institution address
    "INR-SGB": 1000, // 1000 units of Sovereign Gold Bond
    "INR-CORP": 500, // 500 units of Corporate Bond
    "INR-MFD": 2000, // 2000 units of Mutual Fund
  },
};

// Mock protocol custody account
const PROTOCOL_CUSTODY = {
  "INR-SGB": 0,
  "INR-CORP": 0,
  "INR-MFD": 0,
};

// Track transfer history
const TRANSFER_HISTORY = [];

const app = express();
app.use(cors());
app.use(bodyParser.json());

function simulateYieldAccrual() {
  console.log("simulating yield accrual");
  const now = Date.now();
  const oneMinMs = 10 * 1000;

  for (const [key, asset] of Object.entries(ASSET_CATALOG)) {
    const hoursSinceLastYield = Math.floor(
      (now - asset.lastYieldDate) / oneMinMs
    );

    if (hoursSinceLastYield > 0) {
      const hourlyYieldRate = asset.yieldRate / 365 / 24 / 10000;
      const yieldAmount = Prices[key] * hourlyYieldRate * hoursSinceLastYield;

      AccumulatedYields[key] += yieldAmount;
      asset.lastYieldDate = now;

      console.log(`Accrued yield for ${key}: ${yieldAmount.toFixed(4)}`);
    }
  }
}

function simulateMarketMovements() {
  for (const [key, currentPrice] of Object.entries(Prices)) {
    // More realistic market movement with volatility based on asset type
    let volatility = 0.02; // 2% base volatility

    // Adjust volatility based on asset tier
    if (ASSET_CATALOG[key].tier === 1) {
      volatility = 0.01; // Lower volatility for tier 1 (SGB)
    } else if (ASSET_CATALOG[key].tier === 2) {
      volatility = 0.025; // Medium volatility for tier 2 (CORP)
    } else {
      volatility = 0.04; // Higher volatility for tier 3 (MFD)
    }

    // Add some market trend (slight upward bias with random direction changes)
    const trend = (Math.random() - 0.45) * 0.005; // Slight upward bias
    const randomWalk = (Math.random() - 0.5) * volatility;
    const changePercent = trend + randomWalk;

    const newPrice = Math.max(currentPrice * (1 + changePercent), 1);
    Prices[key] = Math.round(newPrice * 100) / 100;
    PriceHistory[key].push({ price: Prices[key], timestamp: Date.now() });

    if (PriceHistory[key].length > 100) {
      PriceHistory[key] = PriceHistory[key].slice(-100);
    }
  }

  console.log("Market prices updated:", Prices);
}

function simulateYieldFluctuation() {
  for (const [key, asset] of Object.entries(ASSET_CATALOG)) {
    // Add some yield rate fluctuation based on market conditions
    const baseYieldRate = asset.yieldRate;
    const yieldVolatility = 0.1; // 10% yield volatility
    const yieldChange = (Math.random() - 0.5) * yieldVolatility;

    // Update yield rate with some persistence (not completely random)
    asset.yieldRate = Math.max(baseYieldRate * (1 + yieldChange), 50); // Minimum 0.5%

    // Add some yield based on current price movements
    const priceChange =
      PriceHistory[key].length > 1
        ? (Prices[key] -
            PriceHistory[key][PriceHistory[key].length - 2].price) /
          PriceHistory[key][PriceHistory[key].length - 2].price
        : 0;

    // Yield increases slightly when prices go up (capital gains effect)
    if (priceChange > 0) {
      asset.yieldRate *= 1 + priceChange * 0.1;
    }
  }
}

// Initialize with some starting data
simulateYieldAccrual();
simulateMarketMovements();

// Root endpoint - API documentation
app.get("/", (req, res) => {
  res.json({
    name: "Mock Custody API",
    version: "1.0.0",
    description: "Simulated custody and asset management API for testing",
    endpoints: {
      "GET /": "API documentation (this endpoint)",
      "GET /assets": "Get all assets with current prices",
      "POST /getAssetPrice":
        "Get price by token address (triggers price simulation)",
      "GET /getTotalYield":
        "Get accumulated yields (triggers yield simulation)",
      "POST /distributeYields": "Distribute and reset yields",
      "GET /prices": "Get all current prices",
      "POST /updatePrice": "Update price by asset key",
      "POST /updatePriceByAddress": "Update price by token address",
      "POST /updatePrices": "Batch update multiple prices",
      "GET /priceHistory/:assetKey": "Get price history for an asset",
      "POST /verify-holdings": "Verify institution holdings",
      "POST /transfer-assets":
        "Transfer assets between institution and protocol",
      "POST /mint-erc20": "Mint ERC20 tokens",
      "GET /holdings/:institutionAddress": "Get institution holdings",
      "GET /protocol-custody": "Get protocol custody",
      "GET /transfer-history": "Get transfer history",
      "GET /simulation-data":
        "Get detailed simulation data (triggers all simulations)",
    },
    simulation: {
      mode: "on-demand",
      description: "Data updates only when endpoints are called",
      assets: Object.keys(ASSET_CATALOG),
      currentPrices: Prices,
      timestamp: Date.now(),
    },
  });
});

app.get("/assets", (req, res) => {
  const out = {};
  for (const [k, v] of Object.entries(ASSET_CATALOG)) {
    out[k] = { ...v, currentPrice: Prices[k] };
    delete out[k].tokenAddr;
  }
  res.json(out);
});

app.post("/getAssetPrice", async (req, res) => {
  try {
    const { assetAddress } = req.body;
    if (!assetAddress) {
      return res.status(400).json({ error: "Asset address is required" });
    }

    const assetKey = Object.keys(ASSET_CATALOG).find(
      (key) =>
        ASSET_CATALOG[key].tokenAddr.toLowerCase() ===
        assetAddress.toLowerCase()
    );

    if (!assetKey) {
      return res.status(404).json({ error: "Asset not found" });
    }

    // Simulate market movement on each price request
    simulateMarketMovements();

    const price = Prices[assetKey];
    const asset = ASSET_CATALOG[assetKey];

    // Add some additional market data
    const priceChange =
      PriceHistory[assetKey].length > 1
        ? Prices[assetKey] -
          PriceHistory[assetKey][PriceHistory[assetKey].length - 2].price
        : 0;

    const priceChangePercent =
      PriceHistory[assetKey].length > 1
        ? (priceChange /
            PriceHistory[assetKey][PriceHistory[assetKey].length - 2].price) *
          100
        : 0;

    res.json({
      price,
      name: asset.name,
      timestamp: Date.now(),
      priceChange,
      priceChangePercent: Math.round(priceChangePercent * 100) / 100,
      assetTier: asset.tier,
      yieldRate: asset.yieldRate,
      marketData: {
        volume: Math.floor(Math.random() * 1000000) + 100000, // Simulated volume
        marketCap: Math.floor(price * Math.random() * 10000000),
        volatility:
          asset.tier === 1 ? "Low" : asset.tier === 2 ? "Medium" : "High",
      },
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.get("/getTotalYield", (req, res) => {
  try {
    // Simulate yield accrual and fluctuation on each request
    simulateYieldAccrual();
    simulateYieldFluctuation();

    console.log("simulated yield with fluctuation");

    const totalYield = Object.values(AccumulatedYields).reduce(
      (sum, yield) => sum + yield,
      0
    );

    // Add some realistic yield distribution patterns
    const yieldsByAsset = {};
    for (const [key, yield] of Object.entries(AccumulatedYields)) {
      const asset = ASSET_CATALOG[key];
      const currentPrice = Prices[key];

      // Calculate yield as percentage of current price
      const yieldPercentage =
        currentPrice > 0 ? (yield / currentPrice) * 100 : 0;

      yieldsByAsset[key] = {
        absoluteYield: yield,
        yieldPercentage: Math.round(yieldPercentage * 100) / 100,
        assetName: asset.name,
        currentPrice: currentPrice,
        yieldRate: asset.yieldRate,
        tier: asset.tier,
      };
    }

    // Add some market sentiment indicators
    const marketSentiment = {
      overallYield:
        Math.round(
          (totalYield /
            Object.values(Prices).reduce((sum, price) => sum + price, 0)) *
            100 *
            100
        ) / 100,
      yieldTrend: Math.random() > 0.5 ? "increasing" : "decreasing",
      marketVolatility: Math.random() * 100,
      riskFreeRate: 2.5 + Math.random() * 2, // Simulated risk-free rate
      yieldSpread: Math.random() * 5 + 1, // Simulated yield spread
    };

    res.json({
      totalYield: Math.floor(totalYield * 1e18),
      yieldsByAsset,
      marketSentiment,
      timestamp: Date.now(),
      simulationData: {
        lastUpdate: new Date().toISOString(),
        yieldAccrualPeriod: "hourly",
        marketMovementFrequency: "on-request",
      },
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.post("/distributeYields", (req, res) => {
  try {
    const totalYield = Object.values(AccumulatedYields).reduce(
      (sum, yield) => sum + yield,
      0
    );

    for (const key in AccumulatedYields) {
      AccumulatedYields[key] = 0;
    }

    res.json({
      distributedYield: Math.floor(totalYield * 1e18),
      message: "Yields distributed and reset",
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.get("/prices", (req, res) => {
  try {
    const pricesWithMetadata = {};
    for (const [key, price] of Object.entries(Prices)) {
      pricesWithMetadata[key] = {
        price,
        name: ASSET_CATALOG[key].name,
        tokenAddr: ASSET_CATALOG[key].tokenAddr,
        lastUpdated: Date.now(),
      };
    }
    res.json(pricesWithMetadata);
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.post("/updatePrice", (req, res) => {
  try {
    const { assetKey, newPrice } = req.body;

    if (!assetKey || newPrice === undefined) {
      return res
        .status(400)
        .json({ error: "assetKey and newPrice are required" });
    }

    if (!ASSET_CATALOG[assetKey]) {
      return res.status(404).json({ error: "Asset not found" });
    }

    if (newPrice <= 0) {
      return res.status(400).json({ error: "Price must be positive" });
    }

    const oldPrice = Prices[assetKey];
    Prices[assetKey] = newPrice;

    PriceHistory[assetKey].push({ price: newPrice, timestamp: Date.now() });
    if (PriceHistory[assetKey].length > 100) {
      PriceHistory[assetKey] = PriceHistory[assetKey].slice(-100);
    }

    console.log(`Price updated for ${assetKey}: ${oldPrice} → ${newPrice}`);

    res.json({
      assetKey,
      oldPrice,
      newPrice,
      name: ASSET_CATALOG[assetKey].name,
      timestamp: Date.now(),
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.post("/updatePriceByAddress", (req, res) => {
  try {
    const { tokenAddress, newPrice } = req.body;

    if (!tokenAddress || newPrice === undefined) {
      return res
        .status(400)
        .json({ error: "tokenAddress and newPrice are required" });
    }

    const assetKey = Object.keys(ASSET_CATALOG).find(
      (key) =>
        ASSET_CATALOG[key].tokenAddr.toLowerCase() ===
        tokenAddress.toLowerCase()
    );

    if (!assetKey) {
      return res.status(404).json({ error: "Asset not found" });
    }

    if (newPrice <= 0) {
      return res.status(400).json({ error: "Price must be positive" });
    }

    const oldPrice = Prices[assetKey];
    Prices[assetKey] = newPrice;

    // Add to price history
    PriceHistory[assetKey].push({ price: newPrice, timestamp: Date.now() });
    if (PriceHistory[assetKey].length > 100) {
      PriceHistory[assetKey] = PriceHistory[assetKey].slice(-100);
    }

    console.log(
      `Price updated for ${assetKey} (${tokenAddress}): ${oldPrice} → ${newPrice}`
    );

    res.json({
      assetKey,
      tokenAddress,
      oldPrice,
      newPrice,
      name: ASSET_CATALOG[assetKey].name,
      timestamp: Date.now(),
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.post("/updatePrices", (req, res) => {
  try {
    const { updates } = req.body;

    if (!updates || !Array.isArray(updates)) {
      return res.status(400).json({ error: "updates array is required" });
    }

    const results = [];
    const errors = [];

    for (const update of updates) {
      const { assetKey, newPrice } = update;

      if (!assetKey || newPrice === undefined) {
        errors.push({ assetKey, error: "assetKey and newPrice are required" });
        continue;
      }

      if (!ASSET_CATALOG[assetKey]) {
        errors.push({ assetKey, error: "Asset not found" });
        continue;
      }

      if (newPrice <= 0) {
        errors.push({ assetKey, error: "Price must be positive" });
        continue;
      }

      const oldPrice = Prices[assetKey];
      Prices[assetKey] = newPrice;

      // Add to price history
      PriceHistory[assetKey].push({ price: newPrice, timestamp: Date.now() });
      if (PriceHistory[assetKey].length > 100) {
        PriceHistory[assetKey] = PriceHistory[assetKey].slice(-100);
      }

      results.push({
        assetKey,
        oldPrice,
        newPrice,
        name: ASSET_CATALOG[assetKey].name,
      });

      console.log(`Price updated for ${assetKey}: ${oldPrice} → ${newPrice}`);
    }

    res.json({
      successful: results,
      errors,
      timestamp: Date.now(),
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.get("/priceHistory/:assetKey", (req, res) => {
  try {
    const { assetKey } = req.params;

    if (!ASSET_CATALOG[assetKey]) {
      return res.status(404).json({ error: "Asset not found" });
    }

    res.json({
      assetKey,
      name: ASSET_CATALOG[assetKey].name,
      history: PriceHistory[assetKey] || [],
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.post("/verify-holdings", (req, res) => {
  try {
    const { institutionAddress, assets, amounts } = req.body;

    if (!institutionAddress || !assets || !amounts) {
      return res.status(400).json({
        error: "institutionAddress, assets, and amounts are required",
      });
    }

    if (assets.length !== amounts.length) {
      return res
        .status(400)
        .json({ error: "assets and amounts arrays must have same length" });
    }

    const holdings = INSTITUTION_HOLDINGS[institutionAddress] || {};
    const verificationResults = [];
    let allVerified = true;

    for (let i = 0; i < assets.length; i++) {
      const assetKey = assets[i];
      const requestedAmount = amounts[i];
      const availableAmount = holdings[assetKey] || 0;

      const isSufficient = availableAmount >= requestedAmount;
      verificationResults.push({
        asset: assetKey,
        requested: requestedAmount,
        available: availableAmount,
        sufficient: isSufficient,
      });

      if (!isSufficient) {
        allVerified = false;
      }
    }

    console.log(
      `Holdings verification for ${institutionAddress}:`,
      verificationResults
    );

    res.json({
      verified: allVerified,
      institutionAddress,
      results: verificationResults,
      message: allVerified
        ? "All holdings verified"
        : "Insufficient holdings for some assets",
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.post("/transfer-assets", (req, res) => {
  try {
    const { fromInstitution, toProtocol, assets, amounts, transferId } =
      req.body;

    if (!fromInstitution || !toProtocol || !assets || !amounts) {
      return res.status(400).json({
        error: "fromInstitution, toProtocol, assets, and amounts are required",
      });
    }

    if (assets.length !== amounts.length) {
      return res
        .status(400)
        .json({ error: "assets and amounts arrays must have same length" });
    }

    // Verify holdings first
    const holdings = INSTITUTION_HOLDINGS[fromInstitution] || {};
    const transferResults = [];

    for (let i = 0; i < assets.length; i++) {
      const assetKey = assets[i];
      const transferAmount = amounts[i];
      const availableAmount = holdings[assetKey] || 0;

      if (availableAmount >= transferAmount) {
        // Deduct from institution holdings
        holdings[assetKey] = availableAmount - transferAmount;

        // Add to protocol custody
        PROTOCOL_CUSTODY[assetKey] =
          (PROTOCOL_CUSTODY[assetKey] || 0) + transferAmount;

        transferResults.push({
          asset: assetKey,
          amount: transferAmount,
          success: true,
          newInstitutionBalance: holdings[assetKey],
          newProtocolBalance: PROTOCOL_CUSTODY[assetKey],
        });
      } else {
        transferResults.push({
          asset: assetKey,
          amount: transferAmount,
          success: false,
          error: "Insufficient holdings",
        });
      }
    }

    // Record transfer
    const transferRecord = {
      transferId: transferId || `transfer_${Date.now()}`,
      fromInstitution,
      toProtocol,
      assets,
      amounts,
      results: transferResults,
      timestamp: Date.now(),
    };

    TRANSFER_HISTORY.push(transferRecord);

    console.log(`Asset transfer completed:`, transferRecord);

    res.json({
      success: transferResults.every((r) => r.success),
      transferId: transferRecord.transferId,
      results: transferResults,
      message: "Transfer completed successfully",
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.post("/mint-erc20", (req, res) => {
  try {
    const { protocolAddress, assets, amounts, recipient } = req.body;

    if (!protocolAddress || !assets || !amounts || !recipient) {
      return res.status(400).json({
        error: "protocolAddress, assets, amounts, and recipient are required",
      });
    }

    if (assets.length !== amounts.length) {
      return res
        .status(400)
        .json({ error: "assets and amounts arrays must have same length" });
    }

    // Verify that protocol has the assets in custody
    const mintResults = [];

    for (let i = 0; i < assets.length; i++) {
      const assetKey = assets[i];
      const mintAmount = amounts[i];
      const custodyAmount = PROTOCOL_CUSTODY[assetKey] || 0;

      if (custodyAmount >= mintAmount) {
        // In a real implementation, this would mint ERC20 tokens
        // For now, we just track the minting
        mintResults.push({
          asset: assetKey,
          amount: mintAmount,
          success: true,
          tokenAddress: ASSET_CATALOG[assetKey]?.tokenAddr,
          recipient,
        });
      } else {
        mintResults.push({
          asset: assetKey,
          amount: mintAmount,
          success: false,
          error: "Insufficient custody balance",
        });
      }
    }

    const tokenizationId = `tokenization_${Date.now()}`;

    console.log(`ERC20 minting completed:`, {
      tokenizationId,
      recipient,
      results: mintResults,
    });

    res.json({
      success: mintResults.every((r) => r.success),
      tokenizationId,
      recipient,
      results: mintResults,
      message: "ERC20 tokens minted successfully",
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.get("/holdings/:institutionAddress", (req, res) => {
  try {
    const { institutionAddress } = req.params;
    const holdings = INSTITUTION_HOLDINGS[institutionAddress] || {};

    res.json({
      institutionAddress,
      holdings,
      timestamp: Date.now(),
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.get("/protocol-custody", (req, res) => {
  try {
    res.json({
      custody: PROTOCOL_CUSTODY,
      timestamp: Date.now(),
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

app.get("/transfer-history", (req, res) => {
  try {
    res.json({
      transfers: TRANSFER_HISTORY,
      count: TRANSFER_HISTORY.length,
    });
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

// New endpoint for detailed simulation data
app.get("/simulation-data", (req, res) => {
  try {
    // Trigger all simulations
    simulateYieldAccrual();
    simulateMarketMovements();
    simulateYieldFluctuation();

    const simulationData = {
      timestamp: Date.now(),
      marketOverview: {
        totalMarketValue: Object.entries(Prices).reduce((sum, [key, price]) => {
          const custodyAmount = PROTOCOL_CUSTODY[key] || 0;
          return sum + price * custodyAmount;
        }, 0),
        averagePrice:
          Object.values(Prices).reduce((sum, price) => sum + price, 0) /
          Object.keys(Prices).length,
        priceVolatility:
          Object.entries(Prices)
            .map(([key, price]) => {
              const history = PriceHistory[key];
              if (history.length < 2) return 0;

              const recentPrices = history.slice(-10);
              const mean =
                recentPrices.reduce((sum, p) => sum + p.price, 0) /
                recentPrices.length;
              const variance =
                recentPrices.reduce(
                  (sum, p) => sum + Math.pow(p.price - mean, 2),
                  0
                ) / recentPrices.length;
              return Math.sqrt(variance) / mean;
            })
            .reduce((sum, vol) => sum + vol, 0) / Object.keys(Prices).length,
      },
      yieldMetrics: {
        totalAccumulatedYield: Object.values(AccumulatedYields).reduce(
          (sum, yield) => sum + yield,
          0
        ),
        averageYieldRate:
          Object.values(ASSET_CATALOG).reduce(
            (sum, asset) => sum + asset.yieldRate,
            0
          ) / Object.keys(ASSET_CATALOG).length,
        yieldByTier: {
          tier1: Object.entries(ASSET_CATALOG)
            .filter(([key, asset]) => asset.tier === 1)
            .reduce(
              (sum, [key, asset]) => sum + (AccumulatedYields[key] || 0),
              0
            ),
          tier2: Object.entries(ASSET_CATALOG)
            .filter(([key, asset]) => asset.tier === 2)
            .reduce(
              (sum, [key, asset]) => sum + (AccumulatedYields[key] || 0),
              0
            ),
          tier3: Object.entries(ASSET_CATALOG)
            .filter(([key, asset]) => asset.tier === 3)
            .reduce(
              (sum, [key, asset]) => sum + (AccumulatedYields[key] || 0),
              0
            ),
        },
      },
      assetDetails: Object.entries(ASSET_CATALOG).map(([key, asset]) => ({
        assetKey: key,
        name: asset.name,
        tier: asset.tier,
        currentPrice: Prices[key],
        yieldRate: asset.yieldRate,
        accumulatedYield: AccumulatedYields[key] || 0,
        priceHistory: PriceHistory[key].slice(-5), // Last 5 price points
        custodyAmount: PROTOCOL_CUSTODY[key] || 0,
        marketValue: Prices[key] * (PROTOCOL_CUSTODY[key] || 0),
      })),
      simulationSettings: {
        yieldAccrualInterval: "on-demand",
        marketMovementInterval: "on-demand",
        yieldFluctuationInterval: "on-demand",
        priceVolatilityByTier: {
          tier1: "1%",
          tier2: "2.5%",
          tier3: "4%",
        },
        simulationMode: "request-triggered",
        description: "Simulation updates only when endpoints are called",
      },
    };

    res.json(simulationData);
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Mock-custody API running at http://localhost:${port}`);
  console.log("\nAvailable endpoints:");
  console.log("GET  /assets - Get all assets");
  console.log("POST /getAssetPrice - Get price by token address");
  console.log("GET  /getTotalYield - Get accumulated yields");
  console.log("POST /distributeYields - Distribute and reset yields");
  console.log("\nPrice Management:");
  console.log("GET  /prices - Get all current prices");
  console.log("POST /updatePrice - Update price by asset key");
  console.log("POST /updatePriceByAddress - Update price by token address");
  console.log("POST /updatePrices - Batch update multiple prices");
  console.log("GET  /priceHistory/:assetKey - Get price history");
  console.log("POST /verify-holdings - Verify institution holdings");
  console.log(
    "POST /transfer-assets - Transfer assets between institution and protocol"
  );
  console.log("POST /mint-erc20 - Mint ERC20 tokens");
  console.log("GET  /holdings/:institutionAddress - Get institution holdings");
  console.log("GET  /protocol-custody - Get protocol custody");
  console.log("GET  /transfer-history - Get transfer history");
  console.log("GET  /simulation-data - Get detailed simulation data");
});
