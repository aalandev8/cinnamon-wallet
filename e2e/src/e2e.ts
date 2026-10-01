import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createPublicClient, createWalletClient, encodeAbiParameters, http, parseEther, toFunctionSelector, type Address } from "viem";
import { createBundlerClient } from "viem/account-abstraction";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
import { foundry } from "viem/chains";
import { MODULE_TYPE_HOOK, toCinnamonAccount, walletAbi } from "./cinnamonAccount.js";

const RPC_URL = process.env.RPC_URL ?? "http://127.0.0.1:8545";
const BUNDLER_URL = process.env.BUNDLER_URL ?? "http://127.0.0.1:4337";
const FUNDER_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const DAILY_LIMIT = parseEther("1");

type Deployment = { entryPoint: Address; factory: Address; ecdsaValidator: Address; spendingLimitHook: Address };
const deployment: Deployment = JSON.parse(
  readFileSync(new URL("../deployments/local.json", import.meta.url), "utf8"),
);

const client = createPublicClient({ chain: foundry, transport: http(RPC_URL) });
const funder = createWalletClient({ account: privateKeyToAccount(FUNDER_KEY), chain: foundry, transport: http(RPC_URL) });
const bundler = createBundlerClient({ client, transport: http(BUNDLER_URL) });

const owner = privateKeyToAccount(generatePrivateKey());
const recipient = privateKeyToAccount(generatePrivateKey()).address;

const account = await toCinnamonAccount({
  client,
  owner,
  entryPoint: deployment.entryPoint,
  factory: deployment.factory,
  rootValidator: deployment.ecdsaValidator,
  extraModules: [
    {
      moduleType: MODULE_TYPE_HOOK,
      moduleAddress: deployment.spendingLimitHook,
      initData: encodeAbiParameters([{ type: "uint256" }], [DAILY_LIMIT]),
    },
  ],
});

async function step(name: string, fn: () => Promise<void>) {
  await fn();
  console.log(`✔ ${name}`);
}

async function send(calls: { to: Address; value: bigint }[]) {
  const hash = await bundler.sendUserOperation({ account, calls });
  return bundler.waitForUserOperationReceipt({ hash });
}

await step("counterfactual address has no code and is funded", async () => {
  assert.equal(await client.getCode({ address: account.address }), undefined);
  await client.waitForTransactionReceipt({
    hash: await funder.sendTransaction({ to: account.address, value: parseEther("5") }),
  });
});

await step("first UserOperation deploys the account and transfers ETH", async () => {
  const receipt = await send([{ to: recipient, value: parseEther("0.4") }]);

  assert.equal(receipt.success, true);
  assert.notEqual(await client.getCode({ address: account.address }), undefined);
  assert.equal(await client.getBalance({ address: recipient }), parseEther("0.4"));
  const hookInstalled = await client.readContract({
    address: account.address,
    abi: walletAbi,
    functionName: "isModuleInstalled",
    args: [MODULE_TYPE_HOOK, deployment.spendingLimitHook, "0x"],
  });
  assert.equal(hookInstalled, true);
});

await step("batch UserOperation executes every call", async () => {
  const receipt = await send([
    { to: recipient, value: parseEther("0.1") },
    { to: recipient, value: parseEther("0.2") },
  ]);

  assert.equal(receipt.success, true);
  assert.equal(await client.getBalance({ address: recipient }), parseEther("0.7"));
});

await step("bundler rejects a UserOperation whose execution exceeds the daily limit", async () => {
  const dailyLimitExceeded = toFunctionSelector("DailyLimitExceeded(uint256,uint256)");

  await assert.rejects(send([{ to: recipient, value: parseEther("0.5") }]), (error: Error) =>
    error.message.includes(dailyLimitExceeded),
  );
  assert.equal(await client.getBalance({ address: recipient }), parseEther("0.7"));
});

console.log("e2e passed");
