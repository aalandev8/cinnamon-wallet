# Architecture Decision Records

Short records of significant, hard-to-reverse decisions. Format: see
[`0000-template.md`](0000-template.md). One decision per file, numbered, never
deleted — a reversed decision gets a new ADR that supersedes the old one.

The consolidated view lives in [`../architecture.md`](../architecture.md).

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-core-from-scratch-with-erc7579.md) | Core from scratch, ERC-7579 interfaces from day 1 | Accepted |
| [0002](0002-erc4337-v08.md) | Build against ERC-4337 v0.8 (EntryPoint 0.8.0) | Accepted |
| [0003](0003-eip1167-clones-non-upgradeable.md) | EIP-1167 clones; Core non-upgradeable | Accepted |
| [0004](0004-multi-validator-nonce-key-routing.md) | Multiple validators routed by the 2D nonce key | Accepted |
| [0005](0005-single-global-hook.md) | Single global hook slot in the Core | Accepted |
| [0006](0006-mandatory-root-validator.md) | Mandatory root validator for brick prevention | Accepted |
| [0007](0007-mvp-vertical-slice.md) | MVP vertical slice — pure ERC-4337 v0.8 loop | Accepted |
| [0008](0008-testing-infra.md) | Testing infrastructure for the ERC-4337 loop | Accepted |
| [0009](0009-spending-limit-hook-mvp.md) | Spending-limit hook (MVP) — native ETH, daily epoch | Accepted |
| [0010](0010-factory-typed-module-array.md) | Factory takes an explicit typed module array | Accepted |
