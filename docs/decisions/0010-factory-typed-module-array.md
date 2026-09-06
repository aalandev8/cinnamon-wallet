# ADR-0010: Factory takes an explicit typed module array

- **Status:** Accepted
- **Date:** 2026-09-06
- **Deciders:** repo owner

## Context

`createAccount` must receive the wallet configuration. What goes in determines
the counterfactual address (via the CREATE2 salt) and how flexible each wallet is.

## Decision

`createAccount(address rootValidator, bytes rootInitData, Module[] extraModules,
bytes32 salt)`, where `Module = struct(uint256 moduleType, address moduleAddress,
bytes initData)`.

The counterfactual address is a function of
`hash(rootValidator + rootInitData + extraModules + salt)` deployed via CREATE2
(`cloneDeterministic`). The Factory exposes a matching `getAddress(...)` view that
mirrors the same hashing.

## Consequences

- Every wallet defines its exact configuration; the config is visible in the
  address derivation (good for learning).
- The SDK reconstructs the address off-chain from the same inputs.
- The Factory does not need redeploying to support new configurations.

## Alternatives considered

- **Predefined template enum** — simplest, easiest-to-predict addresses, but
  limits configs to what the Factory author foresaw; needs a redeploy per template.
- **Opaque `initData` blob** executed on the new account — maximum flexibility,
  but opaque, harder to validate, and easier to break the bootstrap.
