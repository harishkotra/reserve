import { createPublicClient, createWalletClient, http, parseAbi, type Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";
import { config as loadEnv } from "dotenv";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
loadEnv({ path: resolve(here, "../../.env.local") });

export const deployments = JSON.parse(
  readFileSync(resolve(here, "../../config/deployments.json"), "utf8")
).base_sepolia as Record<string, string>;

const pk = process.env.AGENT_PRIVATE_KEY as `0x${string}`;
if (!pk) throw new Error("AGENT_PRIVATE_KEY missing");
export const account = privateKeyToAccount(pk);

export const publicClient = createPublicClient({
  chain: baseSepolia,
  transport: http("https://sepolia.base.org"),
});
export const walletClient = createWalletClient({
  chain: baseSepolia,
  transport: http("https://sepolia.base.org"),
  account,
});

export const vaultAbi = parseAbi([
  "function execute(uint8 action, address asset, uint256 amount) returns (bool, bytes32)",
  "function liquidUsdcUsd8() view returns (uint256)",
  "function stockValueUsd8() view returns (uint256)",
  "function totalBookUsd8() view returns (uint256)",
  "function reserveFloorUsd8() view returns (uint256)",
  "function agent() view returns (address)",
  "event IntentApproved(uint8 indexed action, address indexed asset, uint256 amount)",
  "event IntentRefused(uint8 indexed action, address indexed asset, uint256 amount, bytes32 reason)",
]);

export const guardAbi = parseAbi([
  "struct Intent { uint8 action; address asset; uint256 amountUsd8; }",
  "function check((uint8 action, address asset, uint256 amountUsd8) intent) view returns (bool ok, bytes32 reason)",
  "function maxLtvBps() view returns (uint16)",
  "function feedHeartbeat() view returns (uint64)",
]);

export const marketAbi = parseAbi([
  "function price(address asset) view returns (uint256, uint64)",
  "function paused(address asset) view returns (bool)",
  "function multiplier(address asset) view returns (uint256, bool, uint64)",
]);

export const tokenAbi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
]);

export const A = (v: string) => v as Address;
export const ACTIONS = { BuyStock: 0, SupplyCollateral: 1, Borrow: 2, Repay: 3, WithdrawCollateral: 4 } as const;
