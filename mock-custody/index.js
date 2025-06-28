require('dotenv').config()
const express    = require('express')
const bodyParser = require('body-parser')
const cors       = require('cors')
const { ethers } = require('ethers')

////////////////////////////////////////////////////////////////////////////////
// MOCK INSTITUTION & ASSET CATALOG
////////////////////////////////////////////////////////////////////////////////

const ASSET_CATALOG = {
  "INR-SGB": {
    name:      "Indian Sovereign Gold Bond",
    tier:      1,
    haircutBP: 500,           
    country:   "IN",
    decimals:  18,
    tokenAddr: "0xbDcfBEd3188040926bbEaBD70a25cFbE081F428d",
    yieldRate: 250,           
    lastYieldDate: Date.now(),
  },
  "INR-CORP": {
    name:      "Indian Corporate Bond",
    tier:      2,
    haircutBP: 1000,          
    country:   "IN",
    decimals:  18,
    tokenAddr: "0x4F1F27A247a11b41D85c1D9B22304D8DAB8ae736",
    yieldRate: 800,         
    lastYieldDate: Date.now(),
  },
  "INR-MFD": {
    name:      "Indian Mutual Fund",
    tier:      3,
    haircutBP: 200,       
    country:   "IN",
    decimals:  8,
    tokenAddr: "0x40fA3ffdefa6613680F98F75771b897F8020cdF7",
    yieldRate: 1200,       
    lastYieldDate: Date.now(),
  },
}

const Prices = {
  "INR-SGB": 100,
  "INR-CORP": 1000,
  "INR-MFD": 10
}

const PriceHistory = {
  "INR-SGB": [{ price: 100, timestamp: Date.now() }],
  "INR-CORP": [{ price: 1000, timestamp: Date.now() }],
  "INR-MFD": [{ price: 10, timestamp: Date.now() }]
}

const AccumulatedYields = {
  "INR-SGB": 0,
  "INR-CORP": 0,
  "INR-MFD": 0
}

const app = express()
app.use(cors())
app.use(bodyParser.json())

function simulateYieldAccrual() {
  console.log("simulating yield accrual");
  const now = Date.now()
  const oneMinMs = 10 * 1000  
  
  for (const [key, asset] of Object.entries(ASSET_CATALOG)) {
    const hoursSinceLastYield = Math.floor((now - asset.lastYieldDate) / oneMinMs)
    
    if (hoursSinceLastYield > 0) {
      const hourlyYieldRate = asset.yieldRate / 365 / 24 / 10000 
      const yieldAmount = Prices[key] * hourlyYieldRate * hoursSinceLastYield
      
      AccumulatedYields[key] += yieldAmount
      asset.lastYieldDate = now
      
      console.log(`Accrued yield for ${key}: ${yieldAmount.toFixed(4)}`)
    }
  }
}

function simulateMarketMovements() {
  for (const [key, currentPrice] of Object.entries(Prices)) {
    const changePercent = (Math.random() - 0.5) * 0.04 
    const newPrice = Math.max(currentPrice * (1 + changePercent), 1) 
    Prices[key] = Math.round(newPrice * 100) / 100
    PriceHistory[key].push({ price: Prices[key], timestamp: Date.now() })
    
    if (PriceHistory[key].length > 100) {
      PriceHistory[key] = PriceHistory[key].slice(-100)
    }
  }
  
  console.log('Market prices updated:', Prices)
}

setInterval(simulateYieldAccrual, 60 * 60 * 1000)
simulateYieldAccrual() 

setInterval(simulateMarketMovements, 10 * 1000)


app.get('/assets', (req, res) => {
  const out = {}
  for (const [k, v] of Object.entries(ASSET_CATALOG)) {
    out[k] = { ...v, currentPrice: Prices[k] }
    delete out[k].tokenAddr
  }
  res.json(out)
})

app.post('/getAssetPrice', async (req, res) => {
  try {
    const { assetAddress } = req.body;
    if (!assetAddress) {
      return res.status(400).json({ error: 'Asset address is required' });
    }
    
    const assetKey = Object.keys(ASSET_CATALOG).find(key => 
      ASSET_CATALOG[key].tokenAddr.toLowerCase() === assetAddress.toLowerCase()
    );
    
    if (!assetKey) {
      return res.status(404).json({ error: 'Asset not found' });
    }
    
    const price = Prices[assetKey];
    
    res.json({ 
      price,
      name: ASSET_CATALOG[assetKey].name,
      timestamp: Date.now()
    });
  } catch (err) {
    console.error(err)
    return res.status(500).send('Server error')
  }
})

app.get('/getTotalYield', (req, res) => {
  try {
    simulateYieldAccrual() 
    console.log("simulated yield");
    const totalYield = Object.values(AccumulatedYields).reduce((sum, yield) => sum + yield, 0)
    
    res.json({
      totalYield: Math.floor(totalYield * 1e18), 
      yieldsByAsset: AccumulatedYields
    });
  } catch (err) {
    console.error(err)
    return res.status(500).send('Server error')
  }
})

app.post('/distributeYields', (req, res) => {
  try {
    const totalYield = Object.values(AccumulatedYields).reduce((sum, yield) => sum + yield, 0)
    
    for (const key in AccumulatedYields) {
      AccumulatedYields[key] = 0
    }
    
    res.json({
      distributedYield: Math.floor(totalYield * 1e18),
      message: 'Yields distributed and reset'
    });
  } catch (err) {
    console.error(err)
    return res.status(500).send('Server error')
  }
})

app.get('/prices', (req, res) => {
  try {
    const pricesWithMetadata = {}
    for (const [key, price] of Object.entries(Prices)) {
      pricesWithMetadata[key] = {
        price,
        name: ASSET_CATALOG[key].name,
        tokenAddr: ASSET_CATALOG[key].tokenAddr,
        lastUpdated: Date.now()
      }
    }
    res.json(pricesWithMetadata);
  } catch (err) {
    console.error(err)
    return res.status(500).send('Server error')
  }
})

app.post('/updatePrice', (req, res) => {
  try {
    const { assetKey, newPrice } = req.body;
    
    if (!assetKey || newPrice === undefined) {
      return res.status(400).json({ error: 'assetKey and newPrice are required' });
    }
    
    if (!ASSET_CATALOG[assetKey]) {
      return res.status(404).json({ error: 'Asset not found' });
    }
    
    if (newPrice <= 0) {
      return res.status(400).json({ error: 'Price must be positive' });
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
      timestamp: Date.now()
    });
  } catch (err) {
    console.error(err)
    return res.status(500).send('Server error')
  }
})

app.post('/updatePriceByAddress', (req, res) => {
  try {
    const { tokenAddress, newPrice } = req.body;
    
    if (!tokenAddress || newPrice === undefined) {
      return res.status(400).json({ error: 'tokenAddress and newPrice are required' });
    }
    
    const assetKey = Object.keys(ASSET_CATALOG).find(key => 
      ASSET_CATALOG[key].tokenAddr.toLowerCase() === tokenAddress.toLowerCase()
    );
    
    if (!assetKey) {
      return res.status(404).json({ error: 'Asset not found' });
    }
    
    if (newPrice <= 0) {
      return res.status(400).json({ error: 'Price must be positive' });
    }
    
    const oldPrice = Prices[assetKey];
    Prices[assetKey] = newPrice;
    
    // Add to price history
    PriceHistory[assetKey].push({ price: newPrice, timestamp: Date.now() });
    if (PriceHistory[assetKey].length > 100) {
      PriceHistory[assetKey] = PriceHistory[assetKey].slice(-100);
    }
    
    console.log(`Price updated for ${assetKey} (${tokenAddress}): ${oldPrice} → ${newPrice}`);
    
    res.json({
      assetKey,
      tokenAddress,
      oldPrice,
      newPrice,
      name: ASSET_CATALOG[assetKey].name,
      timestamp: Date.now()
    });
  } catch (err) {
    console.error(err)
    return res.status(500).send('Server error')
  }
})

app.post('/updatePrices', (req, res) => {
  try {
    const { updates } = req.body;
    
    if (!updates || !Array.isArray(updates)) {
      return res.status(400).json({ error: 'updates array is required' });
    }
    
    const results = [];
    const errors = [];
    
    for (const update of updates) {
      const { assetKey, newPrice } = update;
      
      if (!assetKey || newPrice === undefined) {
        errors.push({ assetKey, error: 'assetKey and newPrice are required' });
        continue;
      }
      
      if (!ASSET_CATALOG[assetKey]) {
        errors.push({ assetKey, error: 'Asset not found' });
        continue;
      }
      
      if (newPrice <= 0) {
        errors.push({ assetKey, error: 'Price must be positive' });
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
        name: ASSET_CATALOG[assetKey].name
      });
      
      console.log(`Price updated for ${assetKey}: ${oldPrice} → ${newPrice}`);
    }
    
    res.json({
      successful: results,
      errors,
      timestamp: Date.now()
    });
  } catch (err) {
    console.error(err)
    return res.status(500).send('Server error')
  }
})

app.get('/priceHistory/:assetKey', (req, res) => {
  try {
    const { assetKey } = req.params;
    
    if (!ASSET_CATALOG[assetKey]) {
      return res.status(404).json({ error: 'Asset not found' });
    }
    
    res.json({
      assetKey,
      name: ASSET_CATALOG[assetKey].name,
      history: PriceHistory[assetKey] || []
    });
  } catch (err) {
    console.error(err)
    return res.status(500).send('Server error')
  }
})

const port = process.env.PORT || 3000
app.listen(port, () => {
  console.log(`Mock-custody API running at http://localhost:${port}`)
  console.log('\nAvailable endpoints:')
  console.log('GET  /assets - Get all assets')
  console.log('POST /getAssetPrice - Get price by token address')
  console.log('GET  /getTotalYield - Get accumulated yields')
  console.log('POST /distributeYields - Distribute and reset yields')
  console.log('\nPrice Management:')
  console.log('GET  /prices - Get all current prices')
  console.log('POST /updatePrice - Update price by asset key')
  console.log('POST /updatePriceByAddress - Update price by token address')
  console.log('POST /updatePrices - Batch update multiple prices')
  console.log('GET  /priceHistory/:assetKey - Get price history')
})
