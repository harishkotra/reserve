// Bakes live chain state into web/state.json so the page renders deterministically
// (and so screenshots don't depend on a browser's RPC/CORS luck).
import { createPublicClient, http, parseAbi, formatUnits } from "viem";
import { baseSepolia } from "viem/chains";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const d = JSON.parse(readFileSync(resolve(here, "../config/deployments.json"), "utf8")).base_sepolia;
const c = createPublicClient({ chain: baseSepolia, transport: http("https://sepolia.base.org") });

const vaultAbi = parseAbi(["function totalBookUsd8() view returns (uint256)","function liquidUsdcUsd8() view returns (uint256)","function stockValueUsd8() view returns (uint256)","function reserveFloorUsd8() view returns (uint256)","function debtUsd8() view returns (uint256)"]);
const mAbi = parseAbi(["function price(address) view returns (uint256,uint64)","function paused(address) view returns (bool)","function multiplier(address) view returns (uint256,bool,uint64)"]);

const [book,liquid,stockUsd,floor,debt,px,paused,mult,sym] = await Promise.all([
  c.readContract({address:d.vault,abi:vaultAbi,functionName:"totalBookUsd8"}),
  c.readContract({address:d.vault,abi:vaultAbi,functionName:"liquidUsdcUsd8"}),
  c.readContract({address:d.vault,abi:vaultAbi,functionName:"stockValueUsd8"}),
  c.readContract({address:d.vault,abi:vaultAbi,functionName:"reserveFloorUsd8"}),
  c.readContract({address:d.vault,abi:vaultAbi,functionName:"debtUsd8"}),
  c.readContract({address:d.marketData,abi:mAbi,functionName:"price",args:[d.stock]}),
  c.readContract({address:d.marketData,abi:mAbi,functionName:"paused",args:[d.stock]}),
  c.readContract({address:d.marketData,abi:mAbi,functionName:"multiplier",args:[d.stock]}),
  c.readContract({address:d.stock,abi:parseAbi(["function symbol() view returns (string)"]),functionName:"symbol"}),
]);

// walk back for logs in chunks the public node accepts
// The public RPC caps eth_getLogs at 200 blocks, so the ledger is rebuilt from the
// hashes the agent actually sent (agent/runs.jsonl) — every row is a real receipt.
const hashes = new Set();
for (const f of ["../agent/runs.jsonl", "../config/deployments.json", "../config/extra-txs.json"]) {
  const raw = readFileSync(resolve(here, f), "utf8");
  for (const m of raw.matchAll(/0x[0-9a-f]{64}/g)) hashes.add(m[0]);
}
let logs = [];
for (const h of hashes) {
  try {
    const rc = await c.getTransactionReceipt({ hash: h });
    for (const l of rc.logs) if (l.address.toLowerCase() === d.vault.toLowerCase()) logs.push(l);
  } catch {}
}
logs.sort((a, b) => Number((a.blockNumber ?? 0n) - (b.blockNumber ?? 0n)));

const NAMES = {
  "0x16f8845dcae5e850eef5e63425bb9c683cb1faf23e9034270ae38526b31a2979":"PAUSED_CORPORATE_ACTION",
  "0x3b7ee69f317cbdbc31fe44eee0509abbe45a0e18eb947d5a086057dfb8bf0e8b":"MULTIPLIER_PENDING",
  "0x30fe9211318a9b71263b4f045892f4fd3dc2322b723b935db91f728dc82e08cf":"FEED_STALE",
  "0x8be78c635db8bb7448df29fdda9a4699f7272bf8108480c4c2271f48f34d3aa2":"RESERVE_FLOOR_BREACH",
  "0x0caa0e47682677d3250111072622f28de8dad347a79c2ef5dc835e48117bcee9":"LTV_EXCEEDED",
};
const REF = "0xcfb64b44f4fdef514927cadc0d1852c6feab17389454e02463217541a2779e1e";
const events = logs.slice(-9).reverse().map((l) => {
  const refused = l.topics[0] === REF;
  return {
    refused,
    reason: refused ? (NAMES["0x"+l.data.slice(-64)] ?? "UNKNOWN") : null,
    amountUsd: Number(BigInt("0x"+l.data.slice(2,66))) / 1e6,
    tx: l.transactionHash, block: Number(l.blockNumber ?? 0n),
  };
});

const byReason = {};
for (const l of logs) {
  if (l.topics[0] !== REF) continue;
  const name = NAMES["0x"+l.data.slice(-64)] ?? "UNKNOWN";
  byReason[name] = { tx: l.transactionHash, block: Number(l.blockNumber ?? 0n), amountUsd: Number(BigInt("0x"+l.data.slice(2,66)))/1e6 };
}

writeFileSync(resolve(here, "../web/state.json"), JSON.stringify({
  byReason,
  chain: "Base Sepolia", vault: d.vault, guard: d.guard, stock: d.stock, symbol: sym,
  bookUsd: Number(formatUnits(book,8)), liquidUsd: Number(formatUnits(liquid,8)),
  stockUsd: Number(formatUnits(stockUsd,8)), floorUsd: Number(formatUnits(floor,8)), debtUsd: Number(formatUnits(debt,8)),
  price: Number(formatUnits(px[0],8)), feedAgeSec: Math.max(0, Math.floor(Date.now()/1000) - Number(px[1])),
  paused, multiplier: Number(formatUnits(mult[0],18)), multiplierPending: mult[1],
  totalIntents: logs.length, refusedCount: logs.filter(l=>l.topics[0]===REF).length, events,
}, null, 2));
console.log("state.json written:", logs.length, "intents,", events.filter(e=>e.refused).length, "refused in window");
