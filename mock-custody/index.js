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
  },
  "INR-CORP": {
    name:      "Indian Corporate Bond",
    tier:      2,
    haircutBP: 1000,          // 10%
    country:   "IN",
    decimals:  18,
    tokenAddr: "0x4F1F27A247a11b41D85c1D9B22304D8DAB8ae736",
  },
  "INR-MFD": {
    name:      "Indian Mutual Fund",
    tier:      3,
    haircutBP: 200,           // 2%
    country:   "XAU",
    decimals:  8,
    tokenAddr: "0x40fA3ffdefa6613680F98F75771b897F8020cdF7",
  },
}

const Prices = {
  "INR-SGB": 100,
  "INR-CORP": 1000,
  "INR-MFD": 10
}

const app = express()
app.use(cors())
app.use(bodyParser.json())

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
      assetAddress = "0x40fA3ffdefa6613680F98F75771b897F8020cdF7";
      // return res.status(400).json({ error: 'Asset address is required' });
    }
    const assetKey = Object.keys(ASSET_CATALOG).find(key => 
      ASSET_CATALOG[key].tokenAddr.toLowerCase() === assetAddress.toLowerCase()
    );
    if (!assetKey) {
      return res.status(404).json({ error: 'Asset not found' });
    }
    const price = Prices[assetKey];
    
    res.json({ 
      // assetAddress,
      // assetKey,
      price,
      // name: ASSET_CATALOG[assetKey].name
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
