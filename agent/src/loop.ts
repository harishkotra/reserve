/**
 * Reserve agent loop.
 *
 * The agent never decides "is this safe" on its own. It forms an intent, asks the Guard,
 * and only then moves money. Every refusal is recorded — refusals are the product.
 */
import { formatUnits } from "viem";
import { appendFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import {
  A, ACTIONS, account, deployments, guardAbi, marketAbi, publicClient, tokenAbi, vaultAbi, walletClient,
} from "./chain.js";

const here = dirname(fileURLToPath(import.meta.url));
const LOG = resolve(here, "../runs.jsonl");
const REFUSED_TOPIC = "0xcfb64b44f4fdef514927cadc0d1852c6feab17389454e02463217541a2779e1e" as const;
const APPROVED_TOPIC = "0xa033f4f187f197ba63aa5390fbc18b2b6235228a2f4660ae9b4b5c5f9ca286ae" as const;

const vault = A(deployments.vault);
const guard = A(deployments.guard);
const market = A(deployments.marketData);
const stock = A(deployments.stock);

// policy: keep 40% of the book in the stock, buy in $2 steps, never touch the reserve floor
const TARGET_STOCK_SHARE = 0.4;
const STEP_USD8 = 2n * 10n ** 8n; // guard intent is denominated in USD 8dp
const STEP_USDC6 = 2n * 10n ** 6n; // vault.execute takes token units (USDC is 6dp)

const usd = (v: bigint) => `$${formatUnits(v, 8)}`;

function record(row: Record<string, unknown>) {
  const line = JSON.stringify({ ts: new Date().toISOString(), ...row });
  appendFileSync(LOG, line + "\n");
  console.log(line);
}

async function snapshot() {
  const [book, liquid, stockUsd, floor, price, stale] = await Promise.all([
    publicClient.readContract({ address: vault, abi: vaultAbi, functionName: "totalBookUsd8" }),
    publicClient.readContract({ address: vault, abi: vaultAbi, functionName: "liquidUsdcUsd8" }),
    publicClient.readContract({ address: vault, abi: vaultAbi, functionName: "stockValueUsd8" }),
    publicClient.readContract({ address: vault, abi: vaultAbi, functionName: "reserveFloorUsd8" }),
    publicClient.readContract({ address: market, abi: marketAbi, functionName: "price", args: [stock] }),
    publicClient.readContract({ address: market, abi: marketAbi, functionName: "paused", args: [stock] }),
  ]);
  return { book, liquid, stockUsd, floor, price8: price[0], priceAt: price[1], paused: stale };
}

async function main() {
  const cycles = Number(process.env.CYCLES ?? 5);
  const intervalMs = Number(process.env.INTERVAL_MS ?? 4000);
  record({ event: "boot", agent: account.address, vault, stock, cycles });

  for (let i = 0; i < cycles; i++) {
    const s = await snapshot();
    const share = Number((s.stockUsd * 10_000n) / (s.book === 0n ? 1n : s.book)) / 10_000;
    record({
      event: "snapshot", cycle: i, book: usd(s.book), liquid: usd(s.liquid),
      stock: usd(s.stockUsd), stockShare: share.toFixed(3), price8: s.price8.toString(), paused: s.paused,
    });

    const spendable = s.liquid > s.floor ? s.liquid - s.floor : 0n;
    const wantsMoreStock = share < TARGET_STOCK_SHARE && spendable >= STEP_USD8;

    if (!wantsMoreStock) {
      record({ event: "idle", cycle: i, reason: share >= TARGET_STOCK_SHARE ? "at_target" : "nothing_above_floor" });
      await new Promise((r) => setTimeout(r, intervalMs));
      continue;
    }

    const intent = { action: ACTIONS.BuyStock, asset: stock, amountUsd8: STEP_USD8 };

    // ask the guard first — the agent is not allowed to be the risk engine
    const [ok, reason] = (await publicClient.readContract({
      address: guard, abi: guardAbi, functionName: "check", args: [intent],
    })) as [boolean, `0x${string}`];

    if (!ok) {
      // The agent does not trade — but it still puts the refusal onchain, so the refusal is
      // observable, countable and auditable instead of living in a log file.
      const hash = await walletClient.writeContract({
        address: vault, abi: vaultAbi, functionName: "execute",
        args: [ACTIONS.BuyStock, stock, STEP_USD8],
      });
      const rc = await publicClient.waitForTransactionReceipt({ hash });
      record({
        event: "refused_onchain", cycle: i, tx: hash, block: Number(rc.blockNumber),
        reason, decision: "do not trade", bookUnchanged: true,
      });
      await new Promise((r) => setTimeout(r, intervalMs));
      continue;
    }

    try {
      const hash = await walletClient.writeContract({
        address: vault, abi: vaultAbi, functionName: "execute",
        args: [ACTIONS.BuyStock, stock, STEP_USDC6],
      });
      const rc = await publicClient.waitForTransactionReceipt({ hash });
      const refused = rc.logs.some((l) => l.topics[0] === REFUSED_TOPIC);
      record({
        event: refused ? "refused_onchain" : "executed", cycle: i, tx: hash,
        block: Number(rc.blockNumber), gasUsed: Number(rc.gasUsed),
        reason: refused ? (rc.logs.find((l) => l.topics[0] === REFUSED_TOPIC)?.data.slice(-64) ?? null) : null,
      });
    } catch (e) {
      record({ event: "tx_failed", cycle: i, error: (e as Error).message.slice(0, 200) });
    }
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  record({ event: "halt" });
}

main().catch((e) => { record({ event: "fatal", error: (e as Error).message }); process.exit(1); });
