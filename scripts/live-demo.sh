#!/usr/bin/env bash
# Replays the product beat against the DEPLOYED Base Sepolia contracts. Every line is a real tx.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env.local; set +a
R=https://sepolia.base.org
V=0x7a8B0015be189109458C9b5Cd8b0E63a8958157E
S=0x89f986e4B964d38A28743410dE0460d879E2d3Af

echo "== book before =="
cast call $V 'totalBookUsd8()(uint256)' --rpc-url $R

echo "== corporate action: pause the ticker =="
cast send $S 'setPaused(bool)' true --private-key "$AGENT_PRIVATE_KEY" --rpc-url $R >/dev/null

echo "== agent asks to buy \$5, guard refuses =="
cast send $V 'execute(uint8,address,uint256)' 0 $S 5000000 --private-key "$AGENT_PRIVATE_KEY" --rpc-url $R \
  | grep -E 'transactionHash|status'

echo "== book after: unchanged, nothing moved =="
cast call $V 'totalBookUsd8()(uint256)' --rpc-url $R
cast call $V 'liquidUsdcUsd8()(uint256)' --rpc-url $R

echo "== clear the corporate action, same intent now settles =="
cast send $S 'setPaused(bool)' false --private-key "$AGENT_PRIVATE_KEY" --rpc-url $R >/dev/null
cast send $V 'execute(uint8,address,uint256)' 0 $S 5000000 --private-key "$AGENT_PRIVATE_KEY" --rpc-url $R \
  | grep -E 'transactionHash|status'
cast call $V 'totalBookUsd8()(uint256)' --rpc-url $R
