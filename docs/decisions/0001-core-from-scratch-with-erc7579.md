# ADR-0001: Build the Wallet Core from scratch, adopting ERC-7579 interfaces from day 1

- **Status:** Accepted
- **Date:** 2026-09-06
- **Deciders:** repo owner

## Context

The project's primary goal is to understand smart-account architecture deeply.
The Core is the trust anchor: a bug there drains every wallet. We need a module
system, and ERC-7579 is the emerging standard for portable modules.

## Decision

Write the Core from scratch, adopting the **ERC-7579 module interfaces from the
start**: implement `IERC7579Account` (`installModule` / `uninstallModule` /
`isModuleInstalled` / `execute` with `ModeCode` + `ExecutionCalldata`), support
the four module types (validator, executor, hook, fallback handler), and use
ERC-7201 namespaced storage.

## Consequences

- Maximum learning of the full standard, including execution-mode encoding.
- Third-party audited modules (e.g. Rhinestone) can be reused later.
- Higher upfront complexity and bug surface than a bespoke minimal system.
- The Core must be kept deliberately small; policy lives in modules (see ADR-0007).

## Alternatives considered

- **Fork Kernel / Nexus / Safe7579** — less learning of the Core; faster to modules.
- **Bespoke minimal module system, migrate to 7579 later** — faster start, but
  migration debt and no compatibility with external modules.
