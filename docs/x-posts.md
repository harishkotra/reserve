# Reserve — X drafts

## 01 — main post — attach the video

```
Built Reserve for @buildonbase's Stocks Maxxing: an agent that manages a book of tokenized stocks and refuses to trade when the data is wrong.

Paused ticker → refused.
Stale price feed → refused.
Would breach the reserve floor → refused.

17 intents on Base Sepolia. 14 refusals, all onchain.
```

293 chars

## 02 — thread 2 — what the guard actually is

```
Every money movement routes through one guard: buy, supply, borrow, repay, withdraw. Default deny.

A refusal isn't an error. It's an event on the vault, with a reason hash you can look up. That's the whole point — the no has to be auditable, not a log line in someone's terminal.
```

280 chars

## 03 — thread 3 — the honest testnet answer

```
Testnet has no B20 ticker, so the stock and the price feed are mocks. I said so in the README and on the dashboard instead of hiding it.

Guard and vault bytecode are identical on both chains — only the market-data adapter swaps. 18 tests, 5 against live Base mainnet state.
```

274 chars

## 04 — thread 4 — where it goes

```
Next: the agent pays for its own risk data per call (x402), and the same guard refuses a borrow when a corporate action is pending mid-position.

Repo + docs in the reply. If you've traded tokenized equities onchain, I want the failure case I'm missing.
```

253 chars
