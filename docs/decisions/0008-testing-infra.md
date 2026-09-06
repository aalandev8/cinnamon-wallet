# ADR-0008: Testing infrastructure for the ERC-4337 loop

- **Status:** Accepted
- **Date:** 2026-09-06
- **Deciders:** repo owner

## Context

Strict TDD is in force. How we test the 4337 loop shapes every test. Options
range from a thin EntryPoint mock to a full local bundler.

## Decision

Two layers:

1. **Bulk of TDD:** deploy the real canonical **EntryPoint 0.8** bytecode in the
   Foundry `setUp`, plus a custom Solidity `UserOperation` builder helper that
   builds, EIP-712-signs, and submits ops via `handleOps`. Fast, deterministic,
   no external infra.
2. **A small e2e suite** against **Alto** (bundler) running locally (Docker /
   anvil) to validate the real ERC-7562 simulation rules (opcode / storage
   restrictions) before testnet.

## Consequences

- Most tests are pure Foundry and run in CI with no services.
- The e2e suite needs a local Alto + anvil setup and is slower; it runs
  separately (not on every push).
- The custom builder must track the v0.8 `PackedUserOperation` layout and the
  EIP-712 domain.

## Alternatives considered

- **Pure EntryPoint mock** — fastest to start, but does not model gas accounting,
  2D nonces, or prefund; high risk of false greens. Rejected.
