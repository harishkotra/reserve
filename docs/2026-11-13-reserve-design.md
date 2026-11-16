# Reserve — design doc (Stocks Maxxing, Track 2: Agentic Stock Finance)

**Date:** 2026-11-13 · **Deadline:** Dec 5, 2026 (assume 23:59 PT = 13:29 IST Dec 6) · **Left:** ~548 h
**Entrant:** Harish (solo) · **Track:** 2 — Agentic Stock Finance (idea 2.3, with 2.1 folded in)

## 1. Intent

An agent that earns its own money, keeps an untouchable operating reserve, puts surplus into
tokenized stocks, borrows USDC against that stock when compute bills arrive, and repays from
revenue — **and refuses to move money whenever the stock market's plumbing says the number it
would act on is wrong.**

The product is the refusal. The treasury is the excuse.

## 2. Why this wins

- Track 2 judges read 50% traction. An agent that has a live Aave position, a repayment history,
  and real x402 receipts is unfakeable in a way a portfolio screenshot is not.
- Idea 2.3 is the only item in Base's list needing a credit facility, a reserve policy, revenue
  routing, and a response to a collateral drop. Four moving parts = the field skips it.
- The obvious entries (2.2 research-to-portfolio agent, 3.1 build-your-own index) are already
  crowded: several trackers and index projects are shipping publicly this week.
- Nobody gates actions on the pause/multiplier state. Drift monitoring exists (Blue Hood),
  multiplier history/tax basis exists (Accuren), total-return display exists (Treasures), the
  principal/clip split exists (Talon). None of them *refuse a transaction*.

## 3. Verified facts this is built on

| Fact | Source | Checked |
|---|---|---|
| Token is not a share: dividends/splits land as a multiplier; `balanceOf` never moves | docs.base.org B20 UI Multipliers | 2026-11-13 |
| Live multipliers already ≠ 1: PMc 1.5588, SANc 1.0106, METAc 1.0003, GOOGLc 1.0004, ORCLc 1.00004 | `GET api.coinbase.com/v1/tokenized-stocks` | 2026-11-13 |
| API exposes `nav_price` + `nav_price_updated_at` per ticker (only 4 populated today) | same | 2026-11-13 |
| Coinbase's onchain registry returns **multiplier and pause state in one call** | Chainlink tokenized-equity-feeds docs | 2026-11-13 |
| Chainlink equity feeder = underlying 24/5 price × multiplier; standard `latestRoundData()` | same | 2026-11-13 |
| Aave V4 pauses the affected reserve during corporate actions until the new multiplier is applied | aave.com/blog/coinbase-tokenized-stocks | 2026-11-13 |
| Outside 24/5 hours the feed holds last price; health factor can only move via interest | same | 2026-11-13 |
| API returns no positions, cost basis, or PnL — "your app's own records cover only the trades made through your app" | Tokenized Stocks API overview | 2026-11-13 |
| Aave V4 Equities Hub on Base = `0xa4d5947eb727a052bae69c593ffc84247ec9864e`; stocks are collateral-only, USDC the only borrowable | aave blog + Dune + Gliese | 2026-11-13 |
| B20 Policy Registry on Base = `0x8453000000000000000000000000000000000002`; token factory `0x4bA3E29E254F25E94E61C4c9d67b37027331534D` | `GET api.coinbase.com/v1/tokenized-stocks/chains` | 2026-11-13 |
| Tokenized stocks are Reg S; US persons excluded; issuer policies gate transfers | Coinbase/Aave docs | 2026-11-13 |

## 4. Approaches considered

**A. Lending market** — build our own stock-collateral market. Rejected: Aave V4, Morpho and Euler
already run this on Base. Competing on liquidity in 22 days loses.

**B. Portfolio/attribution tracker** — cost basis + multiplier history. Rejected: Accuren,
Treasures, Tokenzo, BStocks and Talon are already on it; a tracker is not a working-capital product.

**C. Guarded treasury + borrow (chosen)** — the agent owns the money path, uses Aave as the credit
venue, and the differentiator is a policy module that evaluates every intent against
pause/multiplier/feed/reserve state. Unique product, no liquidity war, traction visible onchain.

## 5. Architecture

```
x402-paid service ──USDC──▶ ReserveVault ──intent──▶ Guard (view) ──verdict──▶ Aave V4 / DEX
      ▲                        │                        ▲
      │                        └── event: IntentRefused(reason, ticker, blockTimestamp)
      └── payer receipts       data: Tokenized Stocks API · Chainlink feed · Coinbase registry
```

- `ReserveVault.sol` — holds USDC + B20 collateral; `reserveFloor` immutable per epoch; only
  sends USDC out through `execute(Intent)` after `Guard.check()` returns OK.
- `Guard.sol` — the moat. Stateless view + reason codes. Inputs: ticker address, action
  (BUY_STOCK / BORROW / REPAY / WITHDRAW_COLLATERAL), amount, oracle pause flag, pending
  multiplier + `effectiveAt`, feed `updatedAt` vs heartbeat, current reserve ratio, user mandate.
- Reasons: `PAUSED_CORPORATE_ACTION`, `MULTIPLIER_PENDING`, `FEED_STALE`, `RESERVE_FLOOR_BREACH`,
  `MANDATE_VIOLATION`. Every verdict emits an event, refused ones included — refusals are the
  traction metric.
- Agent runtime (TypeScript) — sells a metered service over x402 (`@x402/express` 2.8.x, CDP
  facilitator), on receipt books revenue → reserve → surplus, then proposes a stock purchase.
- Console (Next.js) — one screen: reserve line, collateral, debt, borrowing cost, next corporate
  action, and the verdict ledger with reason codes.

### The two-leg stock story

- **Leg R (real):** real mainnet B20 position (one ticker) supplied to Aave V4, real USDC borrowed,
  repaid from x402 revenue. This is the traction evidence.
- **Leg F (fixture):** a B20 Asset token we administer, on which we schedule `updateUIMultiplier`
  and flip pause — because Coinbase's registry cannot be paused on demand. Labeled in the UI and
  the video as a controlled corporate-action fixture, not as a Coinbase event.

Dishonesty here would be the one thing judges punish; the fixture is disclosed in README + video.

## 6. Goals / non-goals

- **Goals:** one complete loop (earn → reserve → allocate → borrow → repay) on Base mainnet; a
  visible refusal driven by real chain state; a stress panel showing the unguarded version
  liquidating; a demo post + video; dated build-in-public posts from day one.
- **Non-goals:** own lending market, own DEX, multi-ticker baskets, mobile app, token launch.
- **Anti-goals:** a dashboard with no money path; a simulated revenue number; anything claiming
  shareholder rights; anything claimable by US persons.

## 7. Constraints and gates

- Reg S: US persons excluded. Gate the app at onboarding; the demo wallet is non-US.
- One submission per track; partner prizes may stack.
- Submission needs a public X post with a video demo tagging @buildonbase, plus the form.
- Testnet is allowed and "not judged less favorably", but 50% of the score is verified onchain
  traction — therefore mainnet for the money path.
- Per-track dollar splits are unpublished. Only "$100k+" and "$6,000 best build-in-public" are
  confirmed from Base's own thread. Do not plan around a number.

## 7a. Testnet vs mainnet (decided 2026-11-16)

Rules text, verbatim: *"If deploying to Base or testing a project requires network (gas) fees,
Entrants may use a Base testnet. Testnet Submissions will not be judged less favorably because
they were built on testnet."* No mainnet requirement anywhere in the rules.

Judging, verbatim from @base's thread: *"50% Traction: real usage, verified onchain — 25% Product —
25% Build in public: dated progress posts and community growth."*

Testnet cannot carry this product, proven on 2026-11-16:
- `GET api.coinbase.com/v1/tokenized-stocks/chains` returns exactly one entry: `chain_id 8453`.
- Token factory `0x4bA3E29E254F25E94E61C4c9d67b37027331534D` and supply manager
  `0xD1Ca4dAcdf3231011D175351f1f02D15C7c5664C` return **zero code** on Base Sepolia (84532) and
  code on Base mainnet. PolicyRegistry `0x8453…0002` is likewise absent.
- Aave V4 Equities Hub and Chainlink tokenized-equity feeds exist only on Base mainnet.

=> On testnet the stock leg is a mock ERC-20 we authored; every number in the demo would be ours,
against a criterion that says "real usage, verified onchain". Decision: **money path on mainnet,
float capped at $60 USDC + gas; Sepolia carries only the fixture token that stages a corporate
action (free, disclosed).**

## 8. Calendar (22 days)

| Window | Output |
|---|---|
| Nov 13–15 | repo, fixture B20 deploy on Sepolia, registry/feed probes, Guard spec in tests |
| Nov 16–19 | Vault + Guard implemented, forge tests green, mainnet-fork test against Aave hub |
| Nov 20–23 | x402 service live, agent loop earning real USDC, first receipts |
| Nov 24–27 | Console + verdict ledger; mainnet deploy of vault |
| Nov 28–Dec 1 | real position supplied to Aave, borrow + repay, stress scenario recorded |
| Dec 2–4 | video, README, submission form, post cadence |
| Dec 5 | submit (target Dec 4 22:00 IST — a day early) |

## 9. Risks

- **No eligible stock holding.** If Harish cannot hold a real B20 token, Leg R collapses to
  fixture-only; traction story weakens. Mitigation: DEX route to one ticker, small size ($20–40).
- **Aave caps.** Supply caps on the 8 listed tickers may block a deposit. Mitigation: read caps
  before designing the borrow path; fall back to unborrowed collateral + a disclosed simulation.
- **Real corporate action may not occur inside the window.** Mitigation: the fixture carries the
  refusal beat; a live announced action is a bonus if one appears.
- **x402 payers.** Traction needs external payers. Mitigation: sell the primitives other hackathon
  teams need (multiplier-correct NAV + pause status per ticker) at $0.01/call.
