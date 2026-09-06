# ADR-0009: Spending-limit hook (MVP) — native ETH, fixed daily epoch

- **Status:** Accepted
- **Date:** 2026-09-06
- **Deciders:** repo owner

## Context

The spending-limit hook is the only non-trivial module in the MVP. Its scope
(asset coverage, time-window model, who changes the limit) needs bounding so it
teaches hook mechanics without a calldata-decoding rabbit hole.

## Decision

- **Asset scope:** native ETH only. `preCheck` reads the execution's `value`.
- **Time window:** fixed daily epoch, `epoch = block.timestamp / 1 days`. Spend
  accrues per epoch and resets on epoch change. Revert when the epoch total
  exceeds the limit.
- **Configuration authority:** the limit is changed via `execute` (authorized by
  the root validator).

## Consequences

- Teaches a stateful accumulator + `preCheck` / `postCheck` + epoch logic.
- No ERC20 support in the MVP (a later increment decodes `transfer` /
  `transferFrom` / `approve` against per-token limits).
- Hooks run in the **execution** phase, not validation, so reading
  `block.timestamp` does not violate ERC-7562 bundler rules.

## Alternatives considered

- **Native ETH + ERC20, daily epoch** — more realistic, but adds calldata
  decoding and edge cases (`approve` vs `transfer`, batch `execute`, odd tokens).
- **Per-transaction cap, no time window** — trivial and stateless, but weak as a
  policy and does not exercise the accumulator or `postCheck`.
