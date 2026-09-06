# ADR-0003: Accounts are EIP-1167 clones; the Core is non-upgradeable

- **Status:** Accepted
- **Date:** 2026-09-06
- **Deciders:** repo owner

## Context

The Factory deploys one proxy per wallet pointing at a shared Core
implementation. The proxy pattern fixes the storage and upgrade story for the
life of the project. ERC-7579 already moves most behaviour changes into modules.

## Decision

Use **EIP-1167 minimal proxies (clones)**. The Core implementation is
**non-upgradeable**.

## Consequences

- Factory uses `cloneDeterministic` + CREATE2; cheap deploys.
- No `_authorizeUpgrade`, no ERC-1967 implementation slot for the Core.
- `initialize()` is guarded against re-init; the singleton implementation has
  its initializers disabled so it cannot be hijacked.
- "Upgrade" means deploying a new Core and migrating assets + modules to a new
  wallet address. A migration flow is **out of MVP scope**.
- ERC-7201 namespaced storage is still required to isolate per-module state.
- Behaviour changes go through modules, not Core upgrades.

## Alternatives considered

- **ERC-1967 + UUPS** (Kernel, Nexus) — per-wallet upgrade, stable address, but
  permanent storage-layout compatibility burden and added attack surface.
- **Beacon proxy** — fleet-wide upgrade, but a single point of failure and a
  centralisation / rug risk; needs a governance answer.
