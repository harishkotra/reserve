# Reserve — demo narration

Record this over `assets/video/reserve-demo-silent.mp4` (67s, 1920×1080).
Read it calm and flat — no hype voice. The silences are intentional; let the numbers land.

| in | out | line |
|---|---|---|
| 0:00 | 0:06 | Every agent that touches money fails the same way: it does exactly what it's told, at the worst possible moment. |
| 0:06 | 0:14 | This is Reserve. It runs a book of tokenized stocks on Base. Twenty dollars: eleven in cash, nine in stock, with a five-dollar operating floor. |
| 0:14 | 0:21 | A buy goes through. Two dollars in, shares out, and the guard signs the intent before a cent moves. |
| 0:21 | 0:30 | Then the ticker pauses for a corporate action — a split, a dividend. Same intent, same size. The guard returns PAUSED_CORPORATE_ACTION, and nothing moves. |
| 0:30 | 0:37 | Overnight, the price feed goes quiet. A twenty-four-hour-old quote isn't a price, so the guard returns FEED_STALE. The trade doesn't happen. |
| 0:37 | 0:45 | And the book can't eat its own cushion. A seven-dollar buy that would breach the five-dollar floor is refused, even though the agent wants it. |
| 0:45 | 0:53 | One gate, no side doors. Every movement routes through the guard, and every refusal emits onchain: seventeen intents, fourteen refusals, all auditable. |
| 0:53 | 1:01 | Same bytecode on testnet and mainnet. Eighteen tests, five running against live Base mainnet state. Only the market-data adapter changes. |
| 1:01 | 1:07 | Refusal is the product. Not a safer trade — a trade that never happens when the data can't be trusted. |

## If you want it under 60s

Cut the third row (the approved buy, 0:14–0:21) and the second half of row eight ("Only the market-data adapter changes").
That lands at 59s and still keeps all three refusal reasons.

## Pronunciation

- PAUSED_CORPORATE_ACTION → "paused, corporate action"
- FEED_STALE → "feed stale"
- Base → "base", one syllable, no article
