# ADR-0005: Single global hook slot in the Core

- **Status:** Accepted
- **Date:** 2026-09-06
- **Deciders:** repo owner

## Context

Spending limits and whitelists are both **hooks**: they run `preCheck` /
`postCheck` around every execution. The Core must decide how many hooks it
supports and how they compose. ERC-7579 does not mandate multiple hooks.

## Decision

The Core has **one global hook slot**. `execute` and `executeFromExecutor` call
`hook.preCheck(...)` before the call and `hook.postCheck(context)` after, where
`context` is the bytes returned by `preCheck`.

## Consequences

- Installing a second hook module reverts; the current one must be uninstalled
  first.
- No hook installed → the hook calls are skipped.
- Combining spending limits + whitelist requires a **combined hook** or a
  **multiplexer hook** that fans out to sub-hooks (later work).
- Predictable gas; no hook-ordering semantics to design.

## Alternatives considered

- **Multiple ordered hooks** — composable, but adds ordering semantics, per-hook
  gas, and "one reverting hook blocks everything" plus uninstall-ordering edge cases.
- **Per-module hooks** (Kernel v3) — most granular, most complex to implement and
  reason about early.
