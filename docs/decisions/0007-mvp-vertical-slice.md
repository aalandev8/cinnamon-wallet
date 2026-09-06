# ADR-0007: MVP vertical slice — pure ERC-4337 v0.8 loop

- **Status:** Accepted
- **Date:** 2026-09-06
- **Deciders:** repo owner

## Context

The full module catalogue (multisig, spending limits, recovery, session keys,
whitelists, paymaster) is large. We need a first slice that exercises every
architectural seam without heavy module logic.

## Decision

The MVP is the **pure ERC-4337 v0.8 loop** with the smallest useful module set:

- `WalletFactory` (clone + CREATE2),
- a root **`ECDSAValidator`** module,
- a **`SpendingLimitHook`** module.

The Core exposes install routing for **all four** module types from day 1, but
only the two module implementations above are built for the MVP.

## Consequences

- Proves EntryPoint 0.8 → `validateUserOp` → `execute` → `preCheck` / `postCheck`
  end to end, with counterfactual wallet creation and a real spend policy.
- Multisig validator, recovery (executor), session keys, whitelist and paymaster
  become later increments (see the roadmap in `README.md`).

## Alternatives considered

- **MVP + multisig validator** — validates nonce-key routing earlier, but adds
  signature-encoding surface up front.
- **MVP + recovery** — exercises the executor type and `changeRootValidator`
  early, but is the most ambitious first slice.
