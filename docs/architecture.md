# Architecture

> Checkpoint frozen on **2026-09-06**. Decisions 1–10 below are accepted and drive
> the MVP. Each has a matching ADR in [`decisions/`](decisions/). Open
> sub-decisions are listed at the end and will be resolved before the code they
> affect is written.

## 1. Mental model: two orthogonal layers

**ERC-4337 is the transaction-transport layer. ERC-7579 is the account's internal
architecture layer. They are independent.**

- **ERC-4337** answers: *how does an operation signed by a contract account reach
  the chain without that account being an EOA or holding gas?* → alternative
  mempool, `UserOperation`, `EntryPoint`, bundlers, paymasters.
- **ERC-7579** answers: *how is the account's logic (validation, policy,
  execution) made modular and portable across account implementations?* →
  standardized module types and account interface.

This project builds a **4337-native** account whose internals are **7579-modular**.

## 2. Components

### External (not built here)

| Component | Responsibility |
| --- | --- |
| **EntryPoint 0.8.0** | Canonical singleton. Verification loop + execution loop, gas accounting, 2D nonces, deposits/stakes, bundler refund. The only contract the Core trusts. |
| **Bundler** | Off-chain. Listens to the `UserOperation` mempool, simulates under ERC-7562 rules, bundles, calls `EntryPoint.handleOps`. Infra + test dependency (Alto locally). |

### Built here

| Component | Responsibility |
| --- | --- |
| **WalletCore** | Account implementation. Implements `IAccount` (4337) and `IERC7579Account`. Execution engine, module registry + ERC-7201 storage, hook orchestration, validator routing, brick prevention. Nothing policy-shaped. |
| **Module interfaces** | `IValidator`, `IExecutor`, `IHook`, `IFallbackHandler` per ERC-7579. |
| **Validator modules** | Authorization policy: root ECDSA validator (MVP), multisig, session keys (later). |
| **Hook modules** | Spend/target policy: spending-limit hook (MVP), whitelist (later). |
| **Executor modules** | Recovery (later), automation (later). |
| **WalletFactory** | Deterministic clone deployment (CREATE2) + atomic initialization + `getAddress` view. |
| **Paymaster** | Separate 4337 contract (not a module). Verifying paymaster in a later phase. |

## 3. Communication

```
EntryPoint ──validateUserOp(op, hash, missingFunds)──▶ WalletCore
                                                        │ route by nonce key → validator address
                                                        ▼
                                                   IValidator.validateUserOp ──▶ validationData
WalletCore ──(pays missingAccountFunds)──▶ EntryPoint

EntryPoint ──execute(mode, calldata)──▶ WalletCore
                                         │ hook.preCheck(msg.sender, value, data)
                                         ▼
                                    external call (call / delegatecall / batch)
                                         │ hook.postCheck(context)
                                         ▼
                                    target

Executor module ──executeFromExecutor(mode, calldata)──▶ WalletCore ──(same hook path)──▶ target
Factory ──CREATE2 + initialize(rootValidator, extraModules)──▶ WalletCore
Recovery module ──(post-timelock)── changeRootValidator ──▶ WalletCore
```

Access-control rules enforced by the Core:

- `validateUserOp`: only the EntryPoint.
- `execute`: only the EntryPoint, the account itself (self-call), or an installed executor.
- `installModule` / `uninstallModule` / `changeRootValidator`: only via `execute` or self-call.
- Modules never call each other directly; the Core orchestrates.

## 4. Flows

### Wallet creation (counterfactual, 4337-native)

1. Off-chain: SDK computes `address = Factory.getAddress(rootValidator, rootInitData, extraModules, salt)` (CREATE2, no code yet).
2. The address is funded, or a paymaster will sponsor.
3. First `UserOperation`: `initCode = Factory ++ createAccount(rootValidator, rootInitData, extraModules, salt)`, `nonce` key `0`, real first action in `callData`.
4. `EntryPoint.handleOps`: Factory `cloneDeterministic` → `initialize` (sets root validator + installs extra modules) → `validateUserOp` (routes to root validator) → prefund → `execute` → hooks → action.
5. Later ops carry empty `initCode`.

### Normal transaction

1. SDK builds the `UserOperation`: `sender`, `nonce = EntryPoint.getNonce(account, validatorKey)`, `callData = execute(...)`, gas limits, optional `paymasterAndData`, EIP-712 signature.
2. `eth_sendUserOperation` → bundler → off-chain simulation (ERC-7562) → `handleOps`.
3. EntryPoint **verification loop**: `validateUserOp` → nonce-key routing → validator checks signature and returns `validUntil` / `validAfter`; account pays prefund; paymaster validation if present.
4. EntryPoint **execution loop**: `execute` → `hook.preCheck` (spending limit / whitelist, may revert) → external call → `hook.postCheck` (accrue counters).
5. Paymaster `postOp`; EntryPoint refunds the bundler and returns unused prefund.

Validation and execution are separate phases. During validation the account
cannot touch foreign storage or make arbitrary external calls — this constrains
how validator modules are written.

## 5. Decisions 1–10 (frozen 2026-09-06)

| # | Decision | ADR |
| --- | --- | --- |
| 1 | **Core from scratch, adopting ERC-7579 module interfaces from day 1.** Implement `IERC7579Account` (`installModule`/`uninstallModule`/`execute` with `ModeCode` + `ExecutionCalldata`), the 4 module types, ERC-7201 namespaced storage. Not a fork; not a bespoke minimal module system. | [0001](decisions/0001-core-from-scratch-with-erc7579.md) |
| 2 | **ERC-4337 v0.8 (EntryPoint 0.8.0).** EIP-712 typed `UserOperation` signing (the `userOpHash` passed to the validator is an EIP-712 hash), Solidity `^0.8.28`, transient storage, EIP-7702 compatible, canonical EntryPoint address fixed cross-chain. Not v0.7. | [0002](decisions/0002-erc4337-v08.md) |
| 3 | **Accounts are EIP-1167 minimal proxies (clones); the Core is non-upgradeable.** Factory uses `cloneDeterministic` + CREATE2; the Core implementation is deployed once and immutable; `initialize()` is guarded against re-init; the singleton has initializers disabled. "Upgrade = migrate to a new wallet" (migration flow is out of MVP). Not UUPS, not Beacon. | [0003](decisions/0003-eip1167-clones-non-upgradeable.md) |
| 4 | **Multiple validators, routed by the 2D nonce key.** The Core reads the validator address from the top 192 bits of `userOp.nonce`, checks it is installed, delegates. SDK builds the nonce via `EntryPoint.getNonce(account, validatorKey)`. Enables owner + session keys + multisig to coexist with parallel nonce streams. Not single-active; not signature-prefix. | [0004](decisions/0004-multi-validator-nonce-key-routing.md) |
| 5 | **Single global hook slot in the Core.** `execute` / `executeFromExecutor` call `hook.preCheck` before and `hook.postCheck(context)` after. Installing a second hook reverts; no hook installed → skipped. Compose multiple policies later via a combined/multiplexer hook. Not multiple ordered hooks; not per-module hooks. | [0005](decisions/0005-single-global-hook.md) |
| 6 | **Mandatory root validator.** `initialize()` sets a root validator in a dedicated slot; `uninstallModule` on the root reverts; swap it with an atomic `changeRootValidator(newValidator, initData)` (via `execute`). Nonce key `0` routes to the root; a non-zero key looks up that installed validator. The deploy `UserOperation` uses key `0`. Prevents a zero-validator brick. | [0006](decisions/0006-mandatory-root-validator.md) |
| 7 | **MVP vertical slice = pure ERC-4337 v0.8 loop:** `WalletFactory` + root `ECDSAValidator` + `SpendingLimitHook`. The Core exposes install routing for all 4 module types from day 1, but only these two module implementations are built for the MVP. Multisig / recovery / session keys / whitelist / paymaster are later increments. | [0007](decisions/0007-mvp-vertical-slice.md) |
| 8 | **Testing infra:** real canonical EntryPoint 0.8 bytecode deployed in the Foundry `setUp` + a custom Solidity `UserOperation` builder helper (build / EIP-712 sign / submit via `handleOps`) for the bulk of TDD; **plus** a small end-to-end suite against **Alto** running locally (Docker / anvil) for ERC-7562 bundler rules before testnet. No pure EntryPoint mock. | [0008](decisions/0008-testing-infra.md) |
| 9 | **Spending-limit hook (MVP) = native ETH only, fixed daily epoch.** `preCheck` reads the execution's native `value` and accrues spend per `block.timestamp / 1 days` window; reverts over the limit. The limit is changed via `execute` (authorized by the root validator). No ERC20 calldata decoding, no rolling window, no per-tx-only cap in the MVP. Hooks run in the execution phase, so `block.timestamp` access is fine vs ERC-7562. | [0009](decisions/0009-spending-limit-hook-mvp.md) |
| 10 | **Factory config passing = explicit typed module array.** `createAccount(rootValidator, rootInitData, Module[] extraModules, salt)`, `Module = struct(moduleType, moduleAddress, initData)`. Counterfactual address = `f(hash(rootValidator + rootInitData + extraModules + salt))` via CREATE2. Factory exposes a matching `getAddress(...)` view. Not a template enum; not an opaque `initData` blob. | [0010](decisions/0010-factory-typed-module-array.md) |

## 6. What stays simple for the MVP

| Area | MVP | Later |
| --- | --- | --- |
| Proxy | EIP-1167 clones, non-upgradeable | migration flow |
| Module types with implementations | validator + hook | executor, fallback |
| Root validator | single-owner ECDSA | passkeys |
| Hook | one slot, spending limit only | multiplexer + whitelist |
| Recovery / session keys / multisig | not built | dedicated phases |
| Paymaster | not built | verifying paymaster |
| Bundler in tests | EntryPoint in Foundry + custom builder | + Alto e2e |
| Out of scope | aggregators, EIP-7702, cross-chain, ERC-7484 registry | — |

## 7. Open sub-decisions (not yet frozen)

- **ERC-1271 `isValidSignature`**: support in the MVP? and how is the validator
  routed there (no nonce → likely a signature prefix)?
- **Executor / fallback**: confirm the MVP ships install routing only, with no
  module implementations.
- **Multisig validator**: signature encoding (concatenated + sorted?), EIP-1271
  for contract signers.
- **Recovery**: guardian set shape, threshold, timelock length; confirm it
  rotates the root validator via `changeRootValidator`.
- **Session keys**: policy enforced inside the validator vs delegated to a hook;
  key storage; expiry and scope encoding.
- **Paymaster**: verifying paymaster with an off-chain signer, no ERC20 — confirm.
- **Deploy target**: which testnet after Anvil.
