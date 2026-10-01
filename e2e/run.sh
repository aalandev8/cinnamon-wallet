#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
RPC_URL="http://127.0.0.1:8545"
LOGS="$(mktemp -d)"

# Anvil default accounts: #0 deploys and funds, #1 executes bundles, #2 is the utility wallet.
DEPLOYER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
EXECUTOR_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
UTILITY_KEY="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"

cleanup() { kill $(jobs -p) 2>/dev/null || true; }
trap cleanup EXIT

anvil --port 8545 --silent &
until cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; do sleep 0.2; done

# Alto detects EntryPoint 0.8 by its canonical address, so deploy the official artifact through the
# deterministic deployer (preinstalled on anvil) with the canonical salt.
CREATE2_DEPLOYER="0x4e59b44847b379578588920cA78FbF26c0B4956C"
ENTRY_POINT_SALT="0x0a59dbff790c23c976a548690c27297883cc66b4c67024f9117b0238995e35e9"
ENTRY_POINT="0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108"
ENTRY_POINT_INITCODE="$(node -p "require('@account-abstraction/contracts/artifacts/EntryPoint.json').bytecode")"
cast send "$CREATE2_DEPLOYER" "${ENTRY_POINT_SALT}${ENTRY_POINT_INITCODE#0x}" \
  --rpc-url "$RPC_URL" --private-key "$DEPLOYER_KEY" >"$LOGS/entrypoint.log"
[ "$(cast code "$ENTRY_POINT" --rpc-url "$RPC_URL")" != "0x" ] || { echo "EntryPoint 0.8 deployment failed"; exit 1; }

(cd "$ROOT" && ENTRY_POINT="$ENTRY_POINT" forge script script/Deploy.s.sol --rpc-url "$RPC_URL" --broadcast --private-key "$DEPLOYER_KEY" >"$LOGS/deploy.log")

pnpm exec alto run \
  --entrypoints "$ENTRY_POINT" \
  --executor-private-keys "$EXECUTOR_KEY" \
  --utility-private-key "$UTILITY_KEY" \
  --rpc-url "$RPC_URL" \
  --port 4337 \
  --safe-mode false \
  --deploy-simulations-contract true \
  >"$LOGS/alto.log" 2>&1 &
until curl -sf -X POST -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_supportedEntryPoints","params":[]}' \
  http://127.0.0.1:4337 >/dev/null; do sleep 0.5; done

pnpm test || { echo "Alto log: $LOGS/alto.log"; exit 1; }
