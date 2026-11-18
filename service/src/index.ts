/**
 * Reserve risk oracle, sold per call over x402 (v2 protocol, Base Sepolia).
 *
 * Why anyone pays: the answer is the guard's own verdict plus the reserve state behind it.
 * A caller who trades on a stale price during a corporate action gets liquidated. This costs
 * $0.001 and refuses to answer with a number it cannot stand behind.
 */
import express from "express";
import { paymentMiddleware, x402ResourceServer } from "@x402/express";
import { ExactEvmScheme } from "@x402/evm/exact/server";
import { HTTPFacilitatorClient } from "@x402/core/server";
import { createPublicClient, http, parseAbi, formatUnits, type Address } from "viem";
import { baseSepolia } from "viem/chains";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { config as loadEnv } from "dotenv";

const here = dirname(fileURLToPath(import.meta.url));
loadEnv({ path: resolve(here, "../../.env.local") });

const d = JSON.parse(readFileSync(resolve(here, "../../config/deployments.json"), "utf8")).base_sepolia;
const vault = d.vault as Address, market = d.marketData as Address, stock = d.stock as Address;
const payTo = process.env.AGENT_ADDRESS as Address;

const client = createPublicClient({ chain: baseSepolia, transport: http("https://sepolia.base.org") });
const vaultAbi = parseAbi(["function liquidUsdcUsd8() view returns (uint256)", "function stockValueUsd8() view returns (uint256)", "function totalBookUsd8() view returns (uint256)", "function reserveFloorUsd8() view returns (uint256)"]);
const marketAbi = parseAbi(["function price(address) view returns (uint256, uint64)", "function paused(address) view returns (bool)", "function multiplier(address) view returns (uint256, bool, uint64)"]);

const facilitator = new HTTPFacilitatorClient({ url: process.env.FACILITATOR_URL ?? "https://x402.org/facilitator" });
const resourceServer = new x402ResourceServer(facilitator).register("eip155:84532", new ExactEvmScheme());

const app = express();
app.use(paymentMiddleware({
  "GET /verdict/:asset": {
    accepts: [{ scheme: "exact", price: "$0.001", network: "eip155:84532", payTo }],
    description: "Reserve risk verdict: is this tokenized-stock leg safe to touch right now",
    mimeType: "application/json",
  },
}, resourceServer));

app.get("/verdict/:asset", async (req, res) => {
  const asset = req.params.asset as Address;
  const now = BigInt(Math.floor(Date.now() / 1000));
  const [book, liquid, stockUsd, floor, price, paused, mult] = await Promise.all([
    client.readContract({ address: vault, abi: vaultAbi, functionName: "totalBookUsd8" }),
    client.readContract({ address: vault, abi: vaultAbi, functionName: "liquidUsdcUsd8" }),
    client.readContract({ address: vault, abi: vaultAbi, functionName: "stockValueUsd8" }),
    client.readContract({ address: vault, abi: vaultAbi, functionName: "reserveFloorUsd8" }),
    client.readContract({ address: market, abi: marketAbi, functionName: "price", args: [asset] }),
    client.readContract({ address: market, abi: marketAbi, functionName: "paused", args: [asset] }),
    client.readContract({ address: market, abi: marketAbi, functionName: "multiplier", args: [asset] }),
  ]);
  const stale = price[1] === 0n || now > BigInt(price[1]) + 86400n;
  const pending = mult[1] && BigInt(mult[2]) > now;
  res.json({
    asset,
    safe: !paused && !stale && !pending,
    refusalReason: paused ? "PAUSED_CORPORATE_ACTION" : stale ? "FEED_STALE" : pending ? "MULTIPLIER_PENDING" : null,
    paused, feedStale: stale, multiplier: formatUnits(mult[0], 18), multiplierPending: pending,
    price: Number(formatUnits(price[0], 8)), feedUpdatedAt: Number(price[1]),
    book: Number(formatUnits(book, 8)), liquid: Number(formatUnits(liquid, 8)),
    stock: Number(formatUnits(stockUsd, 8)), reserveFloor: Number(formatUnits(floor, 8)),
    source: "reserve guard @ " + d.guard,
  });
});

app.get("/health", (_req, res) => res.json({ ok: true, payTo, protocol: "x402 v2", network: "eip155:84532" }));
app.listen(8787, () => console.log(`reserve oracle on :8787, payTo ${payTo}`));
