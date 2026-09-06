# ADR-0006: Mandatory root validator for brick prevention

- **Status:** Accepted
- **Date:** 2026-09-06
- **Deciders:** repo owner

## Context

With validators as uninstallable modules (ADR-0004), a wallet that loses its last
validator can never authorize anything again — a permanent brick. The Core needs
a guard, and nonce key `0` needs a defined default validator.

## Decision

Designate a **mandatory root validator**. `initialize()` sets it in a dedicated
storage slot. `uninstallModule` on the root reverts. It is swapped only via an
atomic `changeRootValidator(newValidator, initData)` call (through `execute`).
Nonce key `0` routes to the root; a non-zero key looks up that installed
validator. The deploy `UserOperation` uses key `0`.

## Consequences

- A wallet always has at least one validator; no zero-validator state.
- The root is still a module — swappable in kind, never removable to nothing.
- Minimal extra Core logic (one slot, one guarded path).

## Alternatives considered

- **All validators equal + "cannot uninstall the last one" guard** — more
  symmetric, but requires tracking the installed-validator count and leaves the
  nonce-key-`0` default ill-defined.
- **Core-level `owner` break-glass** — puts authorization logic back into the
  Core (the thing we want to keep out) and creates two validation paths.
