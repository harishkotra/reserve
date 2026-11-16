#!/usr/bin/env bash
# Verifies the exact reads BaseMainnetMarketData performs, against live Base mainnet, for free.
# Every value here was confirmed 2026-11-16 before the adapter was written.
set -euo pipefail
RPC=${RPC:-https://mainnet.base.org}
TOKEN=${TOKEN:-0xb200000000000000000000000D3176ee4af1102d}   # RKTc
echo "token=$TOKEN rpc=$RPC"
echo -n "codesize:        "; cast codesize "$TOKEN" --rpc-url "$RPC"        # 1 => node-native B20
echo -n "code:            "; cast code "$TOKEN" --rpc-url "$RPC"            # 0xef
echo -n "symbol:          "; cast call "$TOKEN" 'symbol()(string)' --rpc-url "$RPC"
echo -n "decimals:        "; cast call "$TOKEN" 'decimals()(uint8)' --rpc-url "$RPC"   # 8, not 18
echo -n "uiMultiplier:    "; cast call "$TOKEN" 'uiMultiplier()(uint256)' --rpc-url "$RPC"
echo -n "effectiveAt:     "; cast call "$TOKEN" 'effectiveAt()(uint64)' --rpc-url "$RPC"
echo -n "pausedFeatures:  "; cast call "$TOKEN" 'pausedFeatures()(string[])' --rpc-url "$RPC"
echo "NOTE: paused() and isPaused() revert on this token. Pause state = pausedFeatures().length > 0."
echo -n "USDC decimals:   "; cast call 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 'decimals()(uint8)' --rpc-url "$RPC"
