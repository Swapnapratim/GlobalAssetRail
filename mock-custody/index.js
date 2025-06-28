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
    haircutBP: 500,           // 5%
    country:   "IN",
    decimals:  18,
    tokenAddr: "0xbDcfBEd3188040926bbEaBD70a25cFbE081F428d",
    yieldRate: 250,           // 2.5% annual yield in basis points
    lastYieldDate: Date.now(),
  },
  "INR-CORP": {
    name:      "Indian Corporate Bond",
    tier:      2,
    haircutBP: 1000,          // 10%
    country:   "IN",
    decimals:  18,
    tokenAddr: "0x4F1F27A247a11b41D85c1D9B22304D8DAB8ae736",
    yieldRate: 800,           // 8% annual yield
    lastYieldDate: Date.now(),
  },
  "INR-MFD": {
    name:      "Indian Mutual Fund",
    tier:      3,
    haircutBP: 200,           // 2%
    country:   "IN",
    decimals:  8,
    tokenAddr: "0x40fA3ffdefa6613680F98F75771b897F8020cdF7",
    yieldRate: 1200,          // 12% annual yield
    lastYieldDate: Date.now(),
  },
}

const Prices = {
  "INR-SGB": 100,
  "INR-CORP": 1000,
  "INR-MFD": 10
}

// accumulated yields per asset
const AccumulatedYields = {
  "INR-SGB": 0,
  "INR-CORP": 0,
  "INR-MFD": 0
}

const app = express()
app.use(cors())
app.use(bodyParser.json())

function simulateYieldAccrual() {
  const now = Date.now()
  const oneDayMs = 24 * 60 * 60 * 1000
  
  for (const [key, asset] of Object.entries(ASSET_CATALOG)) {
    const daysSinceLastYield = Math.floor((now - asset.lastYieldDate) / oneDayMs)
    
    if (daysSinceLastYield > 0) {
      const dailyYieldRate = asset.yieldRate / 365 / 10000 // bp to dec
      const yieldAmount = Prices[key] * dailyYieldRate * daysSinceLastYield
      
      AccumulatedYields[key] += yieldAmount
      asset.lastYieldDate = now
      
      console.log(`Accrued yield for ${key}: ${yieldAmount.toFixed(4)}`)
    }
  }
}

setInterval(simulateYieldAccrual, 60 * 60 * 1000)
simulateYieldAccrual() 

app.get('/assets', (req, res) => {
  const out = {}
  for (const [k, v] of Object.entries(ASSET_CATALOG)) {
    out[k] = { ...v }
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
      name: ASSET_CATALOG[assetKey].name
    });
  } catch (err) {
    console.error(err)
    return res.status(500).send('Server error')
  }
})

app.get('/getTotalYield', (req, res) => {
  try {
    simulateYieldAccrual()
    
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
    
    // Reset accumulated yields
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

const port = process.env.PORT || 3000
app.listen(port, () => {
  console.log(`Mock-custody API running at http://localhost:${port}`)
})
