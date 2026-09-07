# Security Policy

## Project status

cinnamon-wallet is a **learning and portfolio project**. The code is **not
audited** and **must not be used to custody real funds** on any mainnet. It
exists to explore ERC-4337 / ERC-7579 account abstraction from first principles.

## Supported versions

There are no released versions yet. Security fixes are applied to `main` only.

## Reporting a vulnerability

Please **do not open a public issue** for security-sensitive findings.

- Use GitHub's [private vulnerability reporting](https://github.com/aalandev8/cinnamon-wallet/security/advisories/new)
  ("Report a vulnerability" on the *Security* tab), or
- email the maintainer at the address on the GitHub profile.

Include:

- affected contract / commit,
- a description of the issue and its impact,
- a minimal proof of concept or failing test if possible.

## What to expect

- Acknowledgement within a few days (best effort — this is a side project).
- A fix or a documented decision to accept the risk, tracked privately until a
  patch lands on `main`.
- Credit in the changelog / release notes if you want it.

## Scope

In scope: everything under `src/` and `script/`, and the Foundry test harness in
`test/`. Out of scope: third-party dependencies in `lib/` (report those
upstream), CI configuration, and anything explicitly marked as a known
limitation in `docs/`.
