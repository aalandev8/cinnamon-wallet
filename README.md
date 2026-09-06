# cinnamon-wallet

A modular, configurable **Smart Contract Wallet** built to learn Account Abstraction,
protocol architecture, and Solidity in depth.

> Status: **architecture design + repo setup**. No MVP contracts implemented yet.

## Objective

This is a **portfolio project**: the aim is to learn Account Abstraction and
protocol design deeply enough to work professionally with Solidity. Progress,
decisions, and rationale are kept visible (see `docs/`) so the repository doubles
as a worked example.

Design and build, from first principles, a smart account where:

- a **Factory** creates and configures wallets,
- each wallet is a thin **Core**,
- the Core delegates behaviour to **independent modules**,
- and every wallet can run a different configuration.

The goal is understanding, not shipping a product: the Core stays minimal and
every policy (who can sign, what is allowed) lives in a module.

Target modules over time: multisig, spending limits, recovery, session keys,
whitelists, and gas sponsorship via a paymaster.

## Stack

| Area | Choice |
| --- | --- |
| Language | Solidity `0.8.28` |
| Tooling | Foundry (`forge`, `cast`, `anvil`) |
| Libraries | OpenZeppelin Contracts (added in Phase 1) |
| Account Abstraction | ERC-4337 **v0.8** (EntryPoint `0.8.0`) |
| Module system | ERC-7579 interfaces from day 1 |
| EVM target | `cancun` (EntryPoint 0.8 uses transient storage) |

## Current state

- [x] Foundry project scaffolded
- [x] Architecture checkpoint: decisions 1–10 frozen (see `docs/architecture.md`)
- [x] ADRs recorded (`docs/decisions/`)
- [x] CI: `forge fmt --check`, `forge build`, `forge test`
- [ ] MVP contracts — **not started**

## MVP architecture (summary)

The MVP is the **pure ERC-4337 v0.8 loop** with the smallest useful module set.

```
WalletFactory ──cloneDeterministic (CREATE2)──▶ WalletCore proxy (EIP-1167, non-upgradeable)
                 initialize(rootValidator = ECDSAValidator,
                            extraModules  = [SpendingLimitHook])
                         │
EntryPoint 0.8 ──validateUserOp──▶ WalletCore ──route by nonce-key──▶ ECDSAValidator (root)
EntryPoint 0.8 ──execute────────▶ WalletCore ──preCheck ──▶ SpendingLimitHook (ETH / day)
                                       │       ──postCheck──▶ (accrue spend)
                                       ▼
                                  target / EOA
```

Key properties:

- **Core is minimal and non-upgradeable.** It owns execution, module registry +
  namespaced storage (ERC-7201), the hook orchestration loop, and validator routing.
- **Multiple validators**, selected by the 2D nonce key. A **mandatory root
  validator** (default for nonce key `0`) can never be uninstalled.
- **One global hook slot**. Spending limit is native-ETH-only with a fixed daily epoch.
- **Clones** (EIP-1167): "upgrade" means migrating to a new wallet.

Full rationale and the open sub-decisions are in [`docs/architecture.md`](docs/architecture.md).

## Roadmap

| Phase | Scope |
| --- | --- |
| **0 — Setup** *(done)* | Foundry config, docs, ADRs, CI |
| **1 — MVP** | Install deps (OZ + `account-abstraction` v0.8). Core: module management, execution engine, hook loop, validator router, ERC-7201 storage. `ECDSAValidator` (root). `SpendingLimitHook`. `WalletFactory` (clone + CREATE2 + `getAddress`). Foundry harness: real EntryPoint 0.8 + custom `UserOperation` builder. |
| **2 — Multisig** | `MultisigValidator` (signer set + threshold), signature encoding, ERC-1271. |
| **3 — Recovery** | Executor module: guardians + threshold + timelock → `changeRootValidator`. |
| **4 — Session keys** | `SessionKeyValidator` with per-key scope + expiry. |
| **5 — Whitelist** | Whitelist hook + a multiplexer hook to compose it with spending limits. |
| **6 — Paymaster** | Verifying paymaster (off-chain signer, no ERC20). |
| **7 — E2E + deploy** | Small Alto (local bundler) e2e suite; testnet deployment. |
| **Later** | Upgrade/migration story, ERC-7484 module registry, EIP-7702. |

## Development

```shell
forge build          # compile
forge test -vvv      # run tests
forge fmt            # format (CI runs --check)
forge coverage       # coverage report
```

Work follows strict TDD and the rules in [`CLAUDE.md`](CLAUDE.md).

## License

MIT — see [`LICENSE`](LICENSE).
