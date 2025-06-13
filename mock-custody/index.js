// index.js
require('dotenv').config();
const express     = require('express');
const bodyParser  = require('body-parser');
const cors        = require('cors');
const { ethers }  = require('ethers');

const app = express();
app.use(cors());
app.use(bodyParser.json());

// 1) Mock asset catalog
const ASSET_CATALOG = {
  "INR-SOV-01":   { name: "30-day T-bill",      tier: 1, haircutBP: 500, decimals: 18 },
  "INR-CORP-ABC": { name: "Corporate Bond ABC", tier: 2, haircutBP: 1000,decimals: 18 },
  "GOLD-1OZ":     { name: "1oz Gold Token",      tier: 3, haircutBP: 200, decimals: 8  },
  // … add more …
};

// 2) In-memory balances: balances[address][assetKey] = BigNumber
const balances = {};

// 3) Custodian signer
const custodian = new ethers.Wallet(process.env.CUSTODIAN_PRIVATE_KEY);

// 4) List available assets
app.get('/assets', (req, res) => {
  res.json(ASSET_CATALOG);
});

// 5) Deposit endpoint
app.post('/deposit', async (req, res) => {
  try {
    const { address, assetKey, amount, signature, timestamp } = req.body;
    if (!ASSET_CATALOG[assetKey]) 
      return res.status(400).send('Unknown assetKey');

    // Recreate the signed message: ethers.solidityPacked([address,assetKey,amount,timestamp])
    const msg = ethers.utils.solidityPack(
      ['address','string','uint256','uint256'],
      [address, assetKey, amount.toString(), timestamp]
    );
    const msgHash = ethers.utils.keccak256(msg);
    const signer = ethers.utils.recoverAddress(msgHash, signature);

    if (signer.toLowerCase() !== custodian.address.toLowerCase())
      return res.status(401).send('Invalid signature');

    // Store balance
    balances[address] ??= {};
    balances[address][assetKey] = 
      (balances[address][assetKey] || ethers.BigNumber.from(0))
        .add(ethers.BigNumber.from(amount));

    return res.sendStatus(200);
  } catch (e) {
    console.error(e);
    return res.sendStatus(500);
  }
});

// 6) Get balances for an institution
app.get('/balance/:institution', (req, res) => {
  const inst = req.params.institution;
  const result = balances[inst] || {};
  // return raw strings
  Object.keys(result).forEach(k => result[k] = result[k].toString());
  res.json(result);
});

// Start server
const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Mock-custody API listening on http://localhost:${port}`);
});
