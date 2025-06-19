require('dotenv').config()
const express    = require('express')
const bodyParser = require('body-parser')
const cors       = require('cors')
const { ethers } = require('ethers')

////////////////////////////////////////////////////////////////////////////////
// 1) MOCK INSTITUTION & ASSET CATALOG
////////////////////////////////////////////////////////////////////////////////

// One custodian key that signs proof-of-deposit messages:
const custodian = new ethers.Wallet(process.env.CUSTODIAN_PRIVATE_KEY)

// Define all your mock assets, with on-chain token address + tier/haircut etc:
const ASSET_CATALOG = {
  "INR-SOV-01": {
    name:      "30-day T-Bill",
    tier:      1,
    haircutBP: 500,           // 5%
    country:   "IN",
    decimals:  18,
    tokenAddr: "0xAAA…",      // deployed ERC-20 address
  },
  "INR-CORP-ABC": {
    name:      "Corp Bond ABC",
    tier:      2,
    haircutBP: 1000,          // 10%
    country:   "IN",
    decimals:  18,
    tokenAddr: "0xBBB…",
  },
  "GOLD-1OZ": {
    name:      "1oz Gold Token",
    tier:      3,
    haircutBP: 200,           // 2%
    country:   "XAU",
    decimals:  8,
    tokenAddr: "0xCCC…",
  },
  // …add more…
}

// In-memory off-chain balances[institution][assetKey] = BigNumber
const balances = {}

////////////////////////////////////////////////////////////////////////////////
// 2) SET UP ON-CHAIN CONNECTION TO VaultManager
////////////////////////////////////////////////////////////////////////////////

const provider = new ethers.JsonRpcProvider(process.env.RPC_URL)

// For demo, we use the institution’s key to call depositCollateral()
const institutionSigner = new ethers.Wallet(
  process.env.INSTITUTION_PRIVATE_KEY,
  provider
)

// Minimal ABI to call `depositCollateral(address,uint256)`
const VAULT_MANAGER_ABI = [
  "function depositCollateral(address _asset, uint256 _amount) external returns (uint256)"
]

// const vaultManager = new ethers.Contract(
//   process.env.VAULT_MANAGER_ADDRESS,
//   VAULT_MANAGER_ABI,
//   institutionSigner
// )

////////////////////////////////////////////////////////////////////////////////
// 3) EXPRESS SETUP
////////////////////////////////////////////////////////////////////////////////

const app = express()
app.use(cors())
app.use(bodyParser.json())

// Endpoint: list available mock assets
app.get('/assets', (req, res) => {
  // strip BigNumbers to plain JS
  const out = {}
  for (const [k, v] of Object.entries(ASSET_CATALOG)) {
    out[k] = { ...v }
    delete out[k].tokenAddr
  }
  res.json(out)
})

////////////////////////////////////////////////////////////////////////////////
// 4) DEPOSIT ENDPOINT
////////////////////////////////////////////////////////////////////////////////

app.post('/deposit', async (req, res) => {
  try {
    // const { address, assetKey, amount, signature, timestamp } = req.body
    // // 1) Validate assetKey
    // const cfg = ASSET_CATALOG[assetKey]
    // if (!cfg) return res.status(400).send('Unknown assetKey')

    // // 2) Verify custodian’s signature
    // const packed = ethers.solidityPacked(
    //   ['address','string','uint256','uint256'],
    //   [address, assetKey, amount.toString(), timestamp]
    // )
    // const hash    = ethers.keccak256(packed)
    // const signer  = ethers.recoverAddress(hash, signature)
    // if (signer.toLowerCase() !== custodian.address.toLowerCase()) {
    //   return res.status(401).send('Invalid signature')
    // }

    // // 3) Update off-chain balances
    // balances[address]           ||= {}
    // balances[address][assetKey] ||= ethers.BigNumber.from(0)
    // balances[address][assetKey]  = balances[address][assetKey]
    //   .add(ethers.BigNumber.from(amount))

    // // 4) **ON-CHAIN**: call VaultManager.depositCollateral
    // //    - convert to token’s base units
    // const rawAmt = ethers.BigNumber
    //   .from(amount)
    //   .mul(ethers.BigNumber.from(10).pow(cfg.decimals))

    // // (Ensure the institution has approved vaultManager onchain for rawAmt!)
    // const tx = await vaultManager.depositCollateral(cfg.tokenAddr, rawAmt)
    // await tx.wait()

    // return res.send({ success: true, sharesMintedTx: tx.hash })
  } catch (err) {
    console.error(err)
    return res.status(500).send('Server error')
  }
})

////////////////////////////////////////////////////////////////////////////////
// 5) QUERY BALANCES (for Chainlink Functions later)
////////////////////////////////////////////////////////////////////////////////

app.get('/balance/:institution', (req, res) => {
  const inst = req.params.institution
  const bal = balances[inst] || {}
  // return raw strings so JSON serializes cleanly
  const out = {}
  for (const [k, v] of Object.entries(bal)) {
    out[k] = v.toString()
  }
  res.json(out)
})

////////////////////////////////////////////////////////////////////////////////
// 6) LAUNCH
////////////////////////////////////////////////////////////////////////////////

const port = process.env.PORT || 3000
app.listen(port, () => {
  console.log(`Mock-custody API running at http://localhost:${port}`)
})
