# Working rules — cinnamon-wallet

Project-scoped rules. These complement the user's global rules; where this file is
more specific, it wins for this repository.

## Purpose

This is a **learning and portfolio project**: build a modular ERC-4337 / ERC-7579
smart account from first principles, deeply enough to work professionally with
Solidity. Optimise for understanding the protocol, not for speed or feature count.
A clear, minimal, well-tested Core beats a large one. Keep the reasoning visible
(`docs/`), because the repo is also a work sample.

## Architecture authority

- The user makes every significant architecture decision. The assistant proposes
  options **with tradeoffs** and asks one question at a time.
- Frozen decisions live in `docs/architecture.md` and, individually, as ADRs in
  `docs/decisions/`. Do not silently deviate from a frozen decision — reopen it
  with the user first.
- Current checkpoint: ADR-0001 … ADR-0010 (see `docs/decisions/`).

## Core vs modules

- **Wallet Core**: execution engine, module registry + ERC-7201 namespaced
  storage, hook orchestration loop, validator routing, EntryPoint trust anchor,
  brick prevention (mandatory root validator). Nothing else.
- **Modules**: all authorization policy (validators) and all spend/target policy
  (hooks), recovery, automation. If it is a *policy*, it is a module.

## Implementation discipline

- **Strict TDD.** Write a failing test first, make it pass, refactor. No
  production contract lands without tests written before it.
- Do not implement ahead of an agreed scope. "Prepare X" ≠ "implement X".
- Match existing patterns and naming. Keep comment density consistent with
  surrounding code.
- All Solidity targets `0.8.28` / `evm_version = cancun`.

## Standards

- ERC-4337 **v0.8** (EntryPoint `0.8.0`). ERC-7579 module interfaces.
- Reuse audited building blocks (OpenZeppelin, `eth-infinitism/account-abstraction`)
  rather than re-implementing primitives — but understand what they do.

## Language

- Conversation replies: match the user's language (currently Spanish).
- All repository artifacts — code, comments, identifiers, docs, tests, commit
  messages, ADRs — are written in **English**, neutral professional register.

## Git

- **Conventional Commits.** No AI attribution / `Co-Authored-By` lines in commit
  messages.
- Branch off `main`; never commit straight to it.
- Before any commit: `forge fmt --check`, `forge build`, and `forge test` must
  all pass.
- Never `git push` without an explicit request.

## Code graph (graphify)

A graphify code graph tracks symbols and their connections for architecture
questions and impact analysis.

- Rebuild after code changes: `graphify update .` (no LLM needed).
- Query: `graphify query "<question>"`, `graphify god-nodes`, `graphify affected "<X>"`.
- Output lives in `graphify-out/` and is git-ignored (regenerable).
- To wire automatic rebuilds for this machine: `graphify claude install` (adds a
  PreToolUse hook + a section here). Run it yourself so you can approve the hook.

## Definition of done (per change)

1. Tests written first and passing.
2. `forge fmt --check` clean.
3. `forge build` and `forge test` green.
4. Docs / ADRs updated if the change touches architecture.
