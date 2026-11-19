# Reserve — the agent that refuses

An autonomous stock agent on Base that will not trade its owner into a corporate action.

Base's tokenized stocks (B20) pay dividends and split by changing a **multiplier** on the token,
not by moving balances. During a corporate action the ticker pauses. Chainlink's tokenized-equity
feed freezes outside 24/5. Every one of those events makes a normal trading bot reason on numbers
that are wrong. Reserve refuses instead of guessing, and every refusal is an onchain event.

## What is actually built

| Component | File | Status |
|---|---|---|
| Refusal state machine, default-deny on every money movement | `contracts/src/Guard.sol` | done, 12 unit tests |
| Vault that can only execute Guard-approved intents | `contracts/src/ReserveVault.sol` | done |
| Market-data seam: one interface, two adapters | `contracts/src/interfaces/IMarketData.sol`, `contracts/src/BaseMainnetMarketData.sol` | done |
| Testnet deploy, simulated on a Sepolia fork with real Circle USDC | `contracts/script/Deploy.s.sol`, `contracts/test/Deploy.t.sol` | done |
| Mainnet parity on a live Base fork (read-only, no spend) | `contracts/test/Parity.t.sol` | done |
| Agent loop that asks the guard, then broadcasts even the refusals | `agent/src/loop.ts` | done, running |
| Paid risk-oracle API (x402 v2) | `service/src/index.ts`, `service/src/client.ts` | done, settled onchain |
| Dashboard reading the vault live | `web/index.html` + `scripts/snapshot.mjs` | done |

`forge test` -> **18 passed, 0 failed** (12 unit, 5 mainnet-fork parity, 1 full Sepolia deploy flow).

## Deployed on Base Sepolia

* Vault `0x7a8B0015be189109458C9b5Cd8b0E63a8958157E`
* Guard `0x2Bad3aea1BB2E1DdfF51e062855118879BE4845a`
* Market data `0x61f9378893f123863E5298df4E55f48022Cd6CA5`
* TSLAc mock `0x89f986e4B964d38A28743410dE0460d879E2d3Af`

Live proof, both transactions real:

* approved buy `0xb700ed4f…54ba` — 0.02 TSLAc for $5, cash 20 -> 15, book stays $20
* refusal `0x46e588c7…168e` — same $5 intent while the ticker is paused: `IntentRefused`,
  reason `0x16f8845d…` = `keccak256("PAUSED_CORPORATE_ACTION")`, cash unchanged

Replay the whole beat with `./scripts/live-demo.sh`.

## Testnet vs mainnet

Guard and ReserveVault are **byte-identical** on both networks. The only swap is the market-data
adapter, which sits behind `IMarketData`:

* `BaseMainnetMarketData` reads `uiMultiplier()`, `effectiveAt()` and `pausedFeatures()` from the
  token itself and the USD price from Chainlink's tokenized-equity feed.
* `MockMarketData` + `MockB20` reproduce the same shapes on Sepolia.

### Facts verified against live Base mainnet (2026-11-16)

* B20 tokens are **not ordinary EVM contracts**: `RKTc 0xb200...102d` returns `codesize 1`, `code 0xef`.
  The node answers their calls natively, which is why the adapter reads are verified over real RPC in
  `scripts/probe-mainnet.sh` instead of inside a fork.
* Tokenized stocks use **8 decimals**, not 18. The vault reads `decimals()` and the mocks are 8dp.
* `paused()` and `isPaused()` **revert** on a live token. Pause state is `pausedFeatures().length > 0`.
* `uiMultiplier()` = 1e18 on RKTc; `effectiveAt()` = 0 when nothing is scheduled.
* Base USDC `0x8335...2913` is 6 decimals; Aave V4 Equities Hub `0xa4d5...864E` has code.
* `/v1/tokenized-stocks/chains` returns **only 8453** — there is no B20 or Equities Hub on any
  testnet, so the Sepolia build necessarily runs against mocks. Disclosed here, in the video, and in
  every demo post.

## Disclosure

On Base Sepolia the stock token, the price feed and the lending spoke are **mocks**, because
Coinbase's B20 registry and Aave's Equities Hub exist only on mainnet. The contracts that decide
whether money moves are the mainnet contracts, unmodified. `Parity.t.sol` deploys those same bytes
against real mainnet USDC and the real Equities Hub.

## Run it

```bash
forge test                                  # all 18
forge test --match-contract ParityTest      # live Base mainnet reads, zero spend
./scripts/probe-mainnet.sh                  # prints the exact values the adapter consumes
forge script contracts/script/Deploy.s.sol  # deploy (see config/chains.json for addresses)
node scripts/snapshot.mjs                   # rebuild the dashboard state from receipts
cd web && python3 -m http.server 8099       # dashboard at localhost:8099
```

## The ledger as it stands

`node scripts/snapshot.mjs` rebuilds `web/state.json` from the receipts of every transaction the
agent (and the hand-run demos) actually sent. Right now that is **17 intents, 14 refusals, 3
settlements**, with refusals carrying one of three reason hashes:

| reason | what it means | proof |
|---|---|---|
| `PAUSED_CORPORATE_ACTION` | the ticker is paused for a split or dividend | `0x46e588c7…168e` |
| `FEED_STALE` | the price feed is older than the 24h tolerance | `0xec0f108b…f683` |
| `RESERVE_FLOOR_BREACH` | the trade would spend below the operating floor | `0x296a575c…00b0` |

Every refusal is an onchain log, so the count is checkable without trusting this README.

## Paid for its own data

`service/` is an x402 v2 risk oracle: `GET /verdict/:asset` returns 402 with a
`PAYMENT-REQUIRED` header until the caller pays $0.001 in USDC on Base Sepolia. The agent's own
wallet paid it and got the guard verdict back:

* settlement tx `0xbea25be8…482f`, block 60921570, `Transfer` of `0x3e8` (0.001 USDC)
* response: `safe: false`, `refusalReason: FEED_STALE` — the oracle sells the refusal, not a price

```bash
cd service && npm i && npx tsx src/index.ts     # :8787
cd service && npx tsx src/client.ts             # pays and prints the settlement receipt
```

## The demo video

`assets/video/reserve-demo-silent.mp4` — 67s, 1920x1080, no audio on purpose. The narration to
record over it is `docs/narration.md`, timed per slide.

```bash
./scripts/make-video.sh     # re-render slides + reassemble
./scripts/reencode.sh       # re-time existing slides to the narration
```
