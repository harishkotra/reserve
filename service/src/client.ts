/**
 * Pays for one verdict. This is what an external agent does: 402 -> sign USDC transfer -> retry.
 */
import { wrapFetchWithPaymentFromConfig } from "@x402/fetch";
import { ExactEvmScheme } from "@x402/evm";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { config as loadEnv } from "dotenv";

const here = dirname(fileURLToPath(import.meta.url));
loadEnv({ path: resolve(here, "../../.env.local") });
const d = JSON.parse(readFileSync(resolve(here, "../../config/deployments.json"), "utf8")).base_sepolia;

const account = privateKeyToAccount(process.env.AGENT_PRIVATE_KEY as `0x${string}`);
const f = wrapFetchWithPaymentFromConfig(fetch, {
  schemes: [{ network: "eip155:84532", client: new ExactEvmScheme(account) }],
});

const url = process.argv[2] ?? `http://localhost:8787/verdict/${d.stock}`;
const res = await f(url, { method: "GET" });
const body = await res.json();
console.log(JSON.stringify({ status: res.status, paid: res.headers.get("PAYMENT-RESPONSE") ? true : false, body }, null, 2));
