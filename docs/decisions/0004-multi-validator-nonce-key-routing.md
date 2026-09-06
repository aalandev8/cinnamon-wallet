# ADR-0004: Multiple validators, routed by the 2D nonce key

- **Status:** Accepted
- **Date:** 2026-09-06
- **Deciders:** repo owner

## Context

The wallet must eventually run several authorization methods at once (owner,
session keys, multisig). When a `UserOperation` arrives, the Core must pick which
validator validates it. ERC-4337 nonces are 2D: a 192-bit `key` plus a 64-bit
sequence.

## Decision

Install **multiple validators** and **route by the nonce key**: the Core reads
the validator address from the top 192 bits of `userOp.nonce`, checks it is
installed, and delegates `validateUserOp` to it (returning
`SIG_VALIDATION_FAILED` / reverting otherwise).

## Consequences

- The SDK builds the nonce via `EntryPoint.getNonce(account, validatorKey)`.
- Each validator gets an independent nonce stream (parallelism between, e.g.,
  the owner and a session key).
- Matches the emerging convention for v0.8 modular accounts (Kernel v3 style).
- **Sub-decision open:** how the validator is routed for ERC-1271
  `isValidSignature`, where there is no nonce (likely a signature prefix), and
  the default behaviour when the nonce key is `0` (routes to the root validator —
  see ADR-0006).

## Alternatives considered

- **Single active validator** — simplest, but owner and session keys cannot be
  active at the same time.
- **Signature-prefix routing** — does not consume nonce space, but mixes routing
  with signature data and is less aligned with the v0.8 convention.
